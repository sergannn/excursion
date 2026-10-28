#!/usr/bin/env python3
"""Exercise generated SQL against an isolated, disposable local PostgreSQL cluster."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

import prepare_private_import as prep


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pg-bin", type=Path, required=True)
    args = parser.parse_args()
    os.umask(0o077)
    report = json.loads((prep.PRIVATE / "generation_report.json").read_text())
    current = {p.name: prep.sha(p.read_bytes()) for p in (prep.ROOT / "supabase/migrations").glob("*.sql")}
    prep.require(current == report["migration_sha256"], "Migrations changed; regenerate before validation")
    enrollment = json.loads((prep.PRIVATE / "auth_enrollment.json").read_text())["users"]
    prep.require(len(enrollment) == report["auth"]["users"], "Enrollment count mismatch")
    for user in enrollment:
        compatible = bool(prep.password_compatible(user["request"]["body"]["password"]))
        prep.require(user["request_ready"] == compatible, "Enrollment readiness mismatch")
        if user["requires_password_reset"]:
            prep.require(compatible and len(user["request"]["body"]["password"]) >= 43, "Insecure temporary password")
    directory = Path(tempfile.mkdtemp(prefix="pgtest-", dir=prep.PRIVATE))
    socket = directory / "s"
    socket.mkdir(mode=0o700)
    cluster = directory / "db"
    started = False

    def command(name, *argv):
        result = subprocess.run([str(args.pg_bin / name), *map(str, argv)], capture_output=True)
        if result.returncode:
            prep.atomic(prep.PRIVATE / "validation_error.log", result.stderr)
        prep.require(result.returncode == 0, f"Local PostgreSQL {name} failed (details withheld to protect data)")
        return result

    def sql(query=None, file=None, fail=False):
        argv = [str(args.pg_bin / "psql"), "-X", "-A", "-t", "-h", str(socket), "-p", "56483",
                "-d", "postgres", "-v", "ON_ERROR_STOP=1"]
        argv += ["-f", str(file)] if file else ["-c", query]
        result = subprocess.run(argv, capture_output=True)
        if (result.returncode == 0) == fail:
            # SQL errors can include customer data. Keep diagnostic files private.
            prep.atomic(prep.PRIVATE / "validation_error.log", result.stderr)
            raise ValueError("Unexpected SQL result; see ignored validation_error.log locally")
        return result.stdout.decode().strip()

    try:
        command("initdb", "-D", cluster, "--auth=trust", "--encoding=UTF8", "--no-locale")
        command("pg_ctl", "-D", cluster, "-l", directory / "postgres.log", "-o",
                f"-F -k {socket} -p 56483 -c listen_addresses=''", "-w", "start")
        started = True
        sql(file=prep.ROOT / "supabase/tests/bootstrap.sql")
        for migration in sorted((prep.ROOT / "supabase/migrations").glob("*.sql")):
            sql(file=migration)
        sql("CREATE TABLE public.users(id bigint PRIMARY KEY, marker text); INSERT INTO public.users VALUES (721,'unrelated');")
        sentinel = sql("SELECT md5(to_jsonb(u)::text) FROM public.users u;")
        files = report["sql_files"]
        for file in files:
            path = prep.PRIVATE / "sql" / file["name"]
            content = path.read_bytes()
            prep.require(len(content) == file["bytes"] and prep.sha(content) == file["sha256"], "Generated SQL artifact changed")
            prep.require(len(content) < 150_000, "SQL exceeds execute_sql limit")
            if not file["name"].startswith("900"):
                sql(file=path)
        # Missing chunks must block the final transaction without touching targets.
        chunk = next(f["name"] for f in files if f["name"].startswith("0001_"))
        sql(f"DELETE FROM excursion_import.chunks WHERE name={prep.literal(chunk)};")
        final = prep.PRIVATE / "sql/9000_apply_atomically.sql"
        sql(file=final, fail=True)
        prep.require(sql("SELECT count(*) FROM public.profiles;") == "0", "Partial import after missing-chunk failure")
        sql(file=prep.PRIVATE / "sql" / chunk)
        # A bad typed row should fail FK/check constraints and roll back prior tables,
        # trigger DDL and timestamp compatibility changes together.
        booking_id = sql("SELECT min(id) FROM excursion_import.bookings;")
        sql(f"UPDATE excursion_import.bookings SET debt=price+1 WHERE id={booking_id};")
        sql(file=final, fail=True)
        prep.require(sql("SELECT count(*) FROM public.profiles;") == "0", "Partial import after constraint failure")
        prep.require(sql("SELECT count(*) FROM pg_trigger WHERE tgname='set_updated_at' AND tgenabled<>'O';") == "0", "Trigger disable escaped rollback")
        prep.require(sql("SELECT attnotnull FROM pg_attribute WHERE attrelid='public.schedule_templates'::regclass AND attname='created_at';") == "t", "Nullability change escaped rollback")
        for file in files:
            if "_bookings.sql" in file["name"]:
                sql(file=prep.PRIVATE / "sql" / file["name"])
        sql(file=final)
        verify = prep.PRIVATE / "sql/9001_verify.sql"
        first = sql(file=verify)
        checks = [r for r in first.splitlines() if len(r.split("|")) == 6]
        prep.require(len(checks) == 28 and all(r.endswith("|t") for r in checks), "Verification count/checksum mismatch")
        # Preserve a legitimate auth link through rerunning all batches and final apply.
        coordinator = bool(sql("SELECT to_regclass('private.identity_operations');"))
        if coordinator:
            sql("INSERT INTO private.identity_operations(id,actor_id,target_id,action) SELECT '22222222-2222-4222-8222-222222222222'::uuid,id,id,'update' FROM public.profiles ORDER BY id LIMIT 1;")
        sql("INSERT INTO auth.users(id,email,raw_user_meta_data) SELECT '11111111-1111-4111-8111-111111111111'::uuid,email,'{\"identity_operation\":\"22222222-2222-4222-8222-222222222222\"}'::jsonb FROM public.profiles ORDER BY id LIMIT 1;")
        if coordinator:
            sql("DELETE FROM private.identity_operations WHERE id='22222222-2222-4222-8222-222222222222';")
        for file in files:
            sql(file=prep.PRIVATE / "sql" / file["name"])
        second = sql(file=verify)
        prep.require(first == second, "Import is not idempotent")
        prep.require(sql("SELECT count(*) FROM public.profiles WHERE auth_user_id IS NOT NULL;") == "1", "Auth link overwritten")
        prep.require(sentinel == sql("SELECT md5(to_jsonb(u)::text) FROM public.users u;"), "Unrelated users table changed")
        for table in report["table_counts"]:
            maximum = int(sql(f'SELECT coalesce(max(id),0) FROM public.{prep.ident(table)};'))
            nxt = int(sql(f"SELECT nextval(pg_get_serial_sequence('public.{table}','id'));"))
            prep.require(nxt == max(maximum + 1, 1), "Identity sequence mismatch")
        # Extra target rows are never silently deleted.
        sql("INSERT INTO public.excursion_statement_entries(slot_key,entry_key) VALUES('local-test','extra');")
        sql(file=final, fail=True)
        prep.require(sql("SELECT count(*) FROM public.excursion_statement_entries;") == "1", "Extra target row was deleted")
        for entry in json.loads((prep.PRIVATE / "upload_manifest.json").read_text())["rows"]:
            path = prep.PRIVATE / entry["local_file"]
            prep.require(prep.sha(path.read_bytes()) == entry["sha256"], "Photo hash mismatch")
        result = {"postgres_version": sql("SHOW server_version;"), "tables_verified": 28,
                  "rows_verified": report["rows"], "all_sql_executed_twice": True,
                  "missing_chunk_rejected": True, "constraint_failure_rolled_back": True,
                  "extra_target_rows_rejected": True, "public_users_unchanged": True,
                  "auth_link_preserved": True, "identity_sequences_verified": 28,
                  "auth_manifest_users_verified": len(enrollment),
                  "photo_rows_verified": report["photos"]["rows"]}
        prep.atomic(prep.PRIVATE / "validation_report.json", prep.dump(result) + "\n")
        # Successful validation leaves no stale error with source data.
        (prep.PRIVATE / "validation_error.log").unlink(missing_ok=True)
        print(prep.dump(result))
    finally:
        if started:
            command("pg_ctl", "-D", cluster, "-m", "immediate", "-w", "stop")
        shutil.rmtree(directory)


if __name__ == "__main__":
    main()
