#!/usr/bin/env python3
"""Offline, fail-closed excursion import preparation. No network dependencies."""
import argparse
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import re
import secrets
import shutil
import tempfile
from decimal import Decimal
from zoneinfo import ZoneInfo

ROOT = Path(__file__).resolve().parents[1]
PRIVATE = ROOT / "supabase/.private_import"
LIMIT = 145_000  # bytes, including all SQL framing; strictly below 150 KB
SENSITIVE = re.compile(r"password|(^|_)token($|_)|secret|auth_user|remember_token", re.I)
TYPE = r"(?:bigint|integer|smallint|text|boolean|date|time|timestamptz|uuid|jsonb|numeric\(\d+,\d+\)|varchar\(\d+\))"


def require(ok, message):
    if not ok:
        raise ValueError(message)


def dump(value):
    # Preserve JSON numeric types and arbitrary decimal precision inside archives.
    if isinstance(value, Decimal):
        require(value.is_finite(), "Non-finite JSON number")
        return format(value, "f")
    if isinstance(value, dict):
        return "{" + ",".join(dump(k) + ":" + dump(v) for k, v in value.items()) + "}"
    if isinstance(value, (list, tuple)):
        return "[" + ",".join(dump(v) for v in value) + "]"
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"), allow_nan=False)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def literal(value):
    return "'" + str(value).replace("'", "''") + "'"


def ident(value):
    require(bool(re.fullmatch(r"[a-z_][a-z_0-9]*", value)), "Invalid SQL identifier")
    return '"' + value + '"'


def split_columns(body):
    return re.split(r",(?![^()]*\))", body)


def schema():
    """Read this project's CREATE TABLE and ALTER ADD COLUMN grammar, never input keys."""
    tables, refs, sources = {}, {}, {}
    for file in sorted((ROOT / "supabase/migrations").glob("*.sql")):
        sql = file.read_text()
        sources[file.name] = sha(file.read_bytes())
        for match in re.finditer(r"create table public\.(\w+)\s*\((.*?)\n\);", sql, re.S | re.I):
            table, body = match.groups()
            require(table not in tables, "Duplicate migration table")
            tables[table], refs[table] = {}, []
            for line in split_columns(body):
                line = line.strip()
                if re.match(r"(?:unique|check|constraint|primary|foreign)\b", line, re.I):
                    continue
                col = re.match(r'"?(\w+)"?\s+(' + TYPE + r')\b(.*)', line, re.S | re.I)
                # A type ending in ')' has no word boundary; retry explicitly.
                if not col:
                    col = re.match(r'"?(\w+)"?\s+(' + TYPE + r')(\s.*|$)', line, re.S | re.I)
                require(col is not None, f"Unsupported migration column in {table}")
                name, typ, rest = col.groups()
                tables[table][name] = (typ.lower(), "not null" in rest.lower() or "primary key" in rest.lower())
                fk = re.search(r"references public\.(\w+)\((\w+)\)", rest)
                if fk:
                    refs[table].append((name, *fk.groups()))
        for match in re.finditer(r"alter table public\.(\w+)\s+(.*?);", sql, re.S | re.I):
            table, body = match.groups()
            for addition in re.finditer(r"add column (\w+)\s+(" + TYPE + r")", body, re.I):
                name, typ = addition.groups()
                require(table in tables and name not in tables[table], "Unsupported ADD COLUMN")
                tables[table][name] = (typ.lower(), False)
    require(len(tables) == 28 and "users" not in tables, "Expected exactly 28 project tables")
    require(tables["profiles"].pop("auth_user_id", None) is not None, "Missing protected auth link")
    tables["profiles"].pop("auth_login_email", None)
    ordered = []
    while len(ordered) < len(tables):
        ready = [t for t in tables if t not in ordered and all(p in ordered for _, p, _ in refs[t])]
        require(ready, "Cyclic public foreign keys require explicit design")
        ordered.extend(ready)
    return {t: tables[t] for t in ordered}, refs, sources


def no_secrets(value):
    if isinstance(value, dict):
        require(not any(SENSITIVE.search(k) for k in value), "Sensitive key in domain data; refusing SQL generation")
        for v in value.values():
            no_secrets(v)
    elif isinstance(value, list):
        for v in value:
            no_secrets(v)


def normalize(value, typ, timezone):
    if value is None:
        return None
    if typ == "jsonb":
        value = json.loads(value, parse_float=Decimal) if isinstance(value, str) else value
        no_secrets(value)
        return value
    if typ == "boolean":
        require(value in (True, False, 0, 1, "0", "1", "true", "false"), "Invalid boolean")
        return value in (True, 1, "1", "true")
    if typ in ("bigint", "integer", "smallint"):
        n = Decimal(str(value))
        require(n.is_finite() and n == n.to_integral_value(), "Invalid integer")
        return int(n)
    if typ.startswith("numeric"):
        n = Decimal(str(value))
        precision, scale = map(int, re.findall(r"\d+", typ))
        require(n.is_finite() and abs(n) < 10 ** (precision - scale), "Numeric overflow")
        require(n == n.quantize(Decimal(10) ** -scale), "Numeric precision loss")
        return format(n, "f")
    if typ == "timestamptz":
        d = dt.datetime.fromisoformat(str(value).replace("Z", "+00:00"))
        if d.tzinfo is None:
            d = d.replace(tzinfo=timezone)
        return d.astimezone(dt.timezone.utc).isoformat()
    if typ == "date":
        return dt.date.fromisoformat(value).isoformat()
    if typ == "time":
        d = dt.time.fromisoformat(value)
        require(d.tzinfo is None, "Unexpected timezone on SQL time")
        return d.isoformat()
    require(isinstance(value, str) and "\x00" not in value, "Invalid text")
    if typ.startswith("varchar"):
        require(len(value) <= int(re.search(r"\d+", typ)[0]), "Text exceeds varchar limit")
    return value


def load_data(tables, refs, timezone):
    raw = json.loads((PRIVATE / "domain_data.json").read_text(), parse_float=Decimal)["tables"]
    require(set(raw) == set(tables), "Export/migration table mismatch")
    result = {}
    for t, cols in tables.items():
        result[t] = []
        for row in raw[t]:
            require(not set(row) - set(cols), f"Unexpected export columns in {t}")
            no_secrets(row)
            cleaned = {c: normalize(row.get(c), typ, timezone) for c, (typ, _) in cols.items()}
            require(all(cleaned[c] is not None for c, (_, mandatory) in cols.items()
                        if mandatory and not (t == "schedule_templates" and c in ("created_at", "updated_at"))),
                    f"Missing required value in {t}")
            result[t].append(cleaned)
        result[t].sort(key=lambda r: r["id"])
        require(len({r["id"] for r in result[t]}) == len(result[t]), f"Duplicate PK in {t}")
    for t in tables:
        for c, parent, pc in refs[t]:
            keys = {r[pc] for r in result[parent]}
            require(all(r[c] is None or r[c] in keys for r in result[t]), f"Orphan FK: {t}.{c}")
    return result


def atomic(path, content):
    ancestor = path.parent
    while not ancestor.exists():
        ancestor = ancestor.parent
    require(ancestor.resolve().is_relative_to(PRIVATE.resolve()), "Output path escapes private directory")
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    fd, tmp = tempfile.mkstemp(dir=path.parent, prefix=".prepare-")
    try:
        with os.fdopen(fd, "wb") as f:
            f.write(content if isinstance(content, bytes) else content.encode())
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)


def password_compatible(password):
    return (isinstance(password, str) and len(password) >= 8 and len(password.encode()) <= 72
            and not any(ord(character) < 32 or ord(character) == 127 for character in password))


def enrollment(data):
    users = json.loads((PRIVATE / "auth_users.json").read_text())
    profiles = {r["id"]: r for r in data["profiles"]}
    require(len(users) == len(profiles) and {u["profile_id"] for u in users} == set(profiles), "Auth/profile ID mismatch")
    path = PRIVATE / "auth_enrollment.json"
    old = json.loads(path.read_text()) if path.exists() else {"users": []}
    previous = {u["profile_id"]: u for u in old["users"]}
    output = []
    for u in users:
        p = profiles[u["profile_id"]]
        require(p["email"] == u["email"], "Auth/profile email mismatch")
        missing = not u.get("password")
        require(bool(u["requires_password_reset"]) == missing, "Inconsistent password status")
        prior = previous.get(p["id"], {})
        password = u.get("password")
        if missing:
            password = prior.get("request", {}).get("body", {}).get("password") if prior.get("email") == p["email"] else None
            if not password_compatible(password):
                password = "Aa9!" + secrets.token_urlsafe(32)
        body = {k: p[k] for k in ("name", "email", "role_id", "color", "bus_id")}
        body["password"] = password
        output.append({"profile_id": p["id"], "email": p["email"],
                       "password_status": "temporary_reset_required" if missing else "legacy_available",
                       "requires_password_reset": missing,
                       "api_password_policy_compatible": bool(password_compatible(password)),
                       "request_ready": bool(password_compatible(password)),
                       "blocked_reason": None if password_compatible(password) else "legacy_password_rejected_by_current_api_policy",
                       "request": {"method": "PUT", "path": f'/api/users/{p["id"]}', "body": body}})
    atomic(path, dump({"version": 1, "bootstrap_admin_required": True,
                       "api_enrollment_support_must_be_verified": True, "users": output}) + "\n")
    return {"users": len(output), "temporary_passwords": sum(u["requires_password_reset"] for u in output),
            "legacy_passwords_requiring_policy_decision": sum(not u["request_ready"] for u in output)}


def photos(data, source):
    from PIL import Image
    require(source.is_dir(), "Laravel public storage source is unavailable")
    entries, objects = [], {}
    base = PRIVATE / "uploads"
    for row in data["excursion_photos"]:
        key = row["storage_path"]
        require(not Path(key).is_absolute() and ".." not in Path(key).parts, "Unsafe storage path")
        file = (source / key).resolve()
        require(file.is_relative_to(source.resolve()), "Photo symlink escapes source")
        fallback = False
        if not file.is_file():
            candidates = sorted((source / "excursion-photos").glob("showcase-fallback-*.jpg"))
            require(bool(candidates), "No original or existing Laravel fallback photo")
            file = candidates[(row["id"] - 1) % len(candidates)]
            fallback = True
        content = file.read_bytes()
        with Image.open(file) as img:
            img.verify()
        with Image.open(file) as img:
            width, height = img.size
            mime = Image.MIME[img.format]
        meta = {"storage_path": key, "local_file": f"uploads/{key}", "sha256": sha(content),
                "bytes": len(content), "mime_type": mime, "width": width, "height": height,
                "source_relative_path": str(file.relative_to(source.resolve())), "fallback": fallback}
        if key in objects:
            require(objects[key] == meta, "Conflicting files for same storage object")
        else:
            atomic(base / key, content)
            objects[key] = meta
        entries.append({"photo_id": row["id"], "excursion_id": row["excursion_id"], **meta})
    atomic(PRIVATE / "upload_manifest.json", dump({"version": 1, "bucket": "excursion-photos",
           "preserve_storage_path": True, "rows": entries, "objects": list(objects.values())}) + "\n")
    return {"rows": len(entries), "objects": len(objects), "fallback_rows": sum(e["fallback"] for e in entries)}


def names(cols, alias=""):
    return ",".join((alias + "." if alias else "") + ident(c) for c in cols)


def sql_files(tables, data, bundle):
    expected = sum(len(rs) for rs in data.values())
    guard = f"""DO $guard$ BEGIN
 IF (SELECT bundle FROM excursion_import.control WHERE singleton) IS DISTINCT FROM {literal(bundle)}
 THEN RAISE EXCEPTION 'Import bundle mismatch; do not mix runs'; END IF;
END $guard$;
"""
    start = "BEGIN;\nSET LOCAL standard_conforming_strings=on;\nSET LOCAL timezone='UTC';\nSET LOCAL lock_timeout='10s';\nSELECT pg_advisory_xact_lock(6281028);\n"
    files = {}
    pre = start + """CREATE SCHEMA IF NOT EXISTS excursion_import;
REVOKE ALL ON SCHEMA excursion_import FROM PUBLIC, anon, authenticated;
CREATE TABLE IF NOT EXISTS excursion_import.control(singleton boolean PRIMARY KEY CHECK(singleton),bundle text NOT NULL);
CREATE TABLE IF NOT EXISTS excursion_import.chunks(name text PRIMARY KEY, digest text NOT NULL);
""" + f"INSERT INTO excursion_import.control VALUES(true,{literal(bundle)}) ON CONFLICT DO NOTHING;\n" + guard
    for t, cols in tables.items():
        definitions = ",".join(f'{ident(c)} {typ}' for c, (typ, _) in cols.items())
        pre += f"CREATE TABLE IF NOT EXISTS excursion_import.{ident(t)}({definitions},PRIMARY KEY(id));\n"
        # Fail if deployed schema differs from migrations (including type modifiers).
        pre += f"""DO $schema$ BEGIN
 IF EXISTS(SELECT 1 FROM pg_attribute s LEFT JOIN pg_attribute p
 ON p.attrelid='public.{t}'::regclass AND p.attname=s.attname AND p.attnum>0 AND NOT p.attisdropped
 WHERE s.attrelid='excursion_import.{t}'::regclass AND s.attnum>0 AND NOT s.attisdropped
 AND (p.attname IS NULL OR (p.atttypid,p.atttypmod) IS DISTINCT FROM (s.atttypid,s.atttypmod)))
 THEN RAISE EXCEPTION 'Schema mismatch: {t}'; END IF;
END $schema$;
"""
    pre += "REVOKE ALL ON ALL TABLES IN SCHEMA excursion_import FROM PUBLIC, anon, authenticated;\nCOMMIT;\n"
    files["0000_preflight.sql"] = pre
    chunk_names = []
    index = 1
    for t, cols in tables.items():
        definitions = ",".join(f'{ident(c)} {typ}' for c, (typ, _) in cols.items())

        def chunk(rows, filename):
            payload = dump(rows)
            return (start + guard + f"INSERT INTO excursion_import.{ident(t)}({names(cols)})\n"
                    + f"SELECT {names(cols)} FROM jsonb_to_recordset({literal(payload)}::jsonb) AS x({definitions})\n"
                    + "ON CONFLICT(id) DO UPDATE SET " + ",".join(f"{ident(c)}=excluded.{ident(c)}" for c in cols if c != "id")
                    + ";\nINSERT INTO excursion_import.chunks VALUES(" + literal(filename) + "," + literal(sha(payload.encode()))
                    + ") ON CONFLICT(name) DO UPDATE SET digest=excluded.digest;\nCOMMIT;\n")

        pending = []
        for row in data[t]:
            filename = f"{index:04d}_{t}.sql"
            if len(chunk(pending + [row], filename).encode()) >= LIMIT:
                require(bool(pending), f"Single row exceeds SQL limit in {t}")
                files[filename] = chunk(pending, filename)
                chunk_names.append((filename, sha(dump(pending).encode())))
                index += 1
                pending = []
            pending.append(row)
        filename = f"{index:04d}_{t}.sql"
        files[filename] = chunk(pending, filename)
        chunk_names.append((filename, sha(dump(pending).encode())))
        index += 1
    final = start + guard
    final += "LOCK TABLE " + ",".join(f"public.{ident(t)}" for t in tables) + " IN ACCESS EXCLUSIVE MODE;\n"
    final += "LOCK TABLE " + ",".join(f"excursion_import.{ident(t)}" for t in tables) + ",excursion_import.chunks IN SHARE MODE;\n"
    final += "DO $complete$ BEGIN\n"
    final += f"IF (SELECT count(*) FROM excursion_import.chunks)<>{len(chunk_names)} THEN RAISE EXCEPTION 'Missing chunks'; END IF;\n"
    for filename, digest in chunk_names:
        final += f"IF NOT EXISTS(SELECT 1 FROM excursion_import.chunks WHERE name={literal(filename)} AND digest={literal(digest)}) THEN RAISE EXCEPTION 'Missing/incorrect chunk'; END IF;\n"
    for t in tables:
        final += f"IF (SELECT count(*) FROM excursion_import.{ident(t)})<>{len(data[t])} THEN RAISE EXCEPTION 'Staging count: {t}'; END IF;\n"
        final += f"IF EXISTS(SELECT id FROM public.{ident(t)} EXCEPT SELECT id FROM excursion_import.{ident(t)}) THEN RAISE EXCEPTION 'Extra target IDs: {t}; refusing to delete'; END IF;\n"
    # Unknown user triggers may have side effects: reject rather than disable them.
    final += """IF EXISTS(SELECT 1 FROM pg_trigger g WHERE NOT g.tgisinternal
 AND g.tgrelid IN (""" + ",".join(f"'public.{t}'::regclass" for t in tables) + """ )
 AND (g.tgname,g.tgfoid) NOT IN (
 ('set_updated_at','public.set_updated_at()'::regprocedure),
 ('settled_price_changed','private.booking_price_changed()'::regprocedure),
 ('serialize_booking_accounting','private.lock_accounting()'::regprocedure),
 ('settlement_detached','private.settlement_member_changed()'::regprocedure),
 ('profiles_auth_login_email','private.set_auth_login_email()'::regprocedure)))
 THEN RAISE EXCEPTION 'Unexpected project-table trigger'; END IF;
END $complete$;
"""
    # Preserve actual legacy NULL timestamps instead of inventing import dates.
    for c in ("created_at", "updated_at"):
        if any(r[c] is None for r in data["schedule_templates"]):
            final += f"ALTER TABLE public.schedule_templates ALTER COLUMN {ident(c)} DROP NOT NULL;\n"
    disabled = []
    for t in tables:
        triggers = ([] if t.startswith("archived_") else ["set_updated_at"])
        if t == "bookings":
            triggers.append("settled_price_changed")
        for trigger in triggers:
            final += f"DO $trigger$ BEGIN IF NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='public.{t}'::regclass AND tgname='{trigger}' AND tgenabled='O') THEN RAISE EXCEPTION 'Unexpected trigger state'; END IF; END $trigger$;\n"
            final += f"ALTER TABLE public.{ident(t)} DISABLE TRIGGER {ident(trigger)};\n"
            disabled.append((t, trigger))
    for t, cols in tables.items():
        final += f"INSERT INTO public.{ident(t)} AS target({names(cols)}) SELECT {names(cols)} FROM excursion_import.{ident(t)}\n"
        final += "ON CONFLICT(id) DO UPDATE SET " + ",".join(f"{ident(c)}=excluded.{ident(c)}" for c in cols if c != "id")
        final += f" WHERE ROW({names(cols,'target')}) IS DISTINCT FROM ROW({names(cols,'excluded')});\n"
    for t, trigger in disabled:
        final += f"ALTER TABLE public.{ident(t)} ENABLE TRIGGER {ident(trigger)};\n"
    final += "DO $verify$ BEGIN\n"
    for t, cols in tables.items():
        final += f"IF EXISTS((SELECT {names(cols)} FROM public.{ident(t)} EXCEPT SELECT {names(cols)} FROM excursion_import.{ident(t)}) UNION ALL (SELECT {names(cols)} FROM excursion_import.{ident(t)} EXCEPT SELECT {names(cols)} FROM public.{ident(t)})) THEN RAISE EXCEPTION 'Content mismatch: {t}'; END IF;\n"
        # ALTER SEQUENCE is transactional; setval is deliberately avoided.
        final += f"EXECUTE format('ALTER SEQUENCE %s RESTART WITH %s',pg_get_serial_sequence('public.{t}','id')::regclass,(SELECT greatest(coalesce(max(id),0)+1,1) FROM public.{ident(t)}));\n"
    final += "END $verify$;\nCOMMIT;\n"
    files["9000_apply_atomically.sql"] = final
    verify = start + guard
    verify += "LOCK TABLE " + ",".join(f"public.{ident(t)},excursion_import.{ident(t)}" for t in tables) + " IN SHARE MODE;\n"
    queries = []
    for t, cols in tables.items():
        def checksum(schema_name):
            return f"(SELECT md5(coalesce(string_agg(md5(to_jsonb(r)::text),'' ORDER BY id),'')) FROM (SELECT {names(cols)} FROM {schema_name}.{ident(t)}) r)"
        queries.append(f"SELECT '{t}' AS table_name,{len(data[t])}::bigint AS expected_count,(SELECT count(*) FROM public.{ident(t)}) AS actual_count,{checksum('excursion_import')} AS expected_checksum,{checksum('public')} AS actual_checksum")
    verify += "SELECT *,expected_count=actual_count AND expected_checksum=actual_checksum AS ok FROM (\n" + "\nUNION ALL\n".join(queries) + ") v ORDER BY table_name;\n"
    verify += "SELECT user_id,count(*) AS transactions,sum(amount) AS wallet_balance FROM public.wallet_transactions GROUP BY user_id ORDER BY user_id;\n"
    verify += "SELECT count(*) AS bookings,sum(price) AS price,sum(debt) AS debt FROM public.bookings;\n"
    verify += "SELECT count(*) AS settlements,sum(total_amount) AS total_amount FROM public.settlements;\nCOMMIT;\n"
    files["9001_verify.sql"] = verify
    for filename, content in files.items():
        require(len(content.encode()) < LIMIT, f"SQL file too large: {filename}")
        require(content.startswith("BEGIN;\n") and content.endswith("COMMIT;\n"), "Invalid SQL transaction framing")
        require(not re.search(r"\bpublic\.users\b|\bauth\.users\b|DISABLE TRIGGER (ALL|USER)|session_replication_role", content, re.I), "Forbidden SQL operation")
    return files, expected


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-storage", type=Path, required=True, help="Read-only Laravel storage/app/public")
    parser.add_argument("--source-timezone", default="UTC", help="Timezone of naive legacy timestamps (Laravel config defaults to UTC)")
    args = parser.parse_args()
    os.umask(0o077)
    require(PRIVATE.is_dir(), "Private exports missing")
    require(not PRIVATE.is_symlink(), "Private directory must not be a symlink")
    require(shutil.which("git") is not None, "git required to verify private ignore rule")
    import subprocess
    ignored = subprocess.run(["git", "check-ignore", "-q", str(PRIVATE / "auth_enrollment.json")], cwd=ROOT)
    require(ignored.returncode == 0, "Private directory must be gitignored")
    tracked = subprocess.run(["git", "ls-files", "--", "supabase/.private_import"], cwd=ROOT, capture_output=True)
    require(not tracked.stdout, "Private data is tracked; remove it from Git before proceeding")
    tables, refs, sources = schema()
    data = load_data(tables, refs, ZoneInfo(args.source_timezone))
    bundle = sha(dump({"data": data, "migrations": sources, "timezone": args.source_timezone}).encode())
    files, total = sql_files(tables, data, bundle)
    auth = enrollment(data)
    images = photos(data, args.source_storage.resolve())
    output = PRIVATE / "sql"
    output.mkdir(exist_ok=True, mode=0o700)
    require(not output.is_symlink(), "SQL output must not be a symlink")
    for existing in output.glob("*.sql"):
        if existing.name not in files:
            existing.unlink()
    for filename, content in files.items():
        atomic(output / filename, content)
    report = {"version": 1, "bundle": bundle, "source_timezone": args.source_timezone,
              "migration_sha256": sources, "table_counts": {t: len(rs) for t, rs in data.items()},
              "rows": total, "nullable_timestamp_compatibility": [
                  f"schedule_templates.{c}" for c in ("created_at", "updated_at")
                  if any(r[c] is None for r in data["schedule_templates"])],
              "sql_files": [{"name": n, "bytes": len(c.encode()), "sha256": sha(c.encode())} for n, c in files.items()],
              "auth": auth, "photos": images}
    atomic(PRIVATE / "generation_report.json", dump(report) + "\n")
    print(dump({"tables": len(tables), "rows": total, "sql_files": len(files),
                "max_sql_bytes": max(len(c.encode()) for c in files.values()), "auth": auth, "photos": images}))


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        # Do not echo parser errors, data values, passwords, or exception reprs.
        print(f"Preparation failed ({type(exc).__name__}); inspect inputs locally. No credentials logged.")
        raise SystemExit(1)
