# Private one-time import preparation

Run from `/Users/servas/booking_krym_supabase`. These tools are offline: they never
connect to Supabase, enroll accounts, upload assets, or modify the Laravel tree.
Existing migrations and `supabase/functions/api` are not edited.

Requires Python 3.10+, Pillow (`PIL`), Git, and the existing exports
`supabase/.private_import/domain_data.json` and `auth_users.json`. Local SQL
validation additionally requires PostgreSQL 15+ binaries (`initdb`, `pg_ctl`,
`psql`); this workspace was tested with PostgreSQL 18. All generated customer
data, SQL, passwords, copied assets and reports stay inside the already ignored
`supabase/.private_import/`, with private directory/file permissions (0700/0600).
Do not force-add this directory to Git or copy SQL into issues or logs.

## Generate and validate locally

```sh
python3 tools/prepare_private_import.py \
  --source-storage /Volumes/ExternalSSD/server_mirrors/77.222.47.218/files/www/excursion.panfilius.ru/storage/app/public \
  --source-timezone UTC

python3 tools/validate_private_import.py \
  --pg-bin /Applications/Postgres.app/Contents/Versions/18/bin
```

The source storage argument is read-only; use the actual Laravel public storage
directory if the mirror is elsewhere. The generator reads only referenced photo
files and existing `showcase-fallback-*.jpg` files when an original is absent.
Pillow checks image integrity, MIME type and dimensions. Each manifest entry has
the photo/excursion IDs, source-relative filename, fallback status, destination
object key, size and SHA-256. Paths remain unchanged: upload to bucket
`excursion-photos` using the full `storage_path` as the object key (including its
`excursion-photos/` prefix). Multiple rows may share an object. No storage upload
SQL or network operation is produced.

The validator creates a disposable cluster **inside the private directory**, with
TCP disabled, applies the existing migrations and runs all SQL twice. It checks
28 table counts and complete typed-row checksums, identity sequences, preservation
of an existing auth link, a sentinel unrelated `public.users` table, image hashes,
and full transaction rollback on missing chunks and constraint errors. Extra
target IDs must be rejected. The cluster is stopped and removed in `finally`.
If interrupted forcibly, inspect private `pgtest-*` directories and stop their
cluster with `pg_ctl -D <directory>/db stop` before removing them. A sandbox that
blocks PostgreSQL shared memory needs permission for this local validation only.
Diagnostic SQL errors are written only to ignored `validation_error.log` because
PostgreSQL errors may contain source values; it is removed after success.

## Artifacts and later execution order

* `generation_report.json`: counts, migration fingerprints, bundle ID, SQL sizes
  and SHA-256 hashes, photo/auth totals, timestamp compatibility changes.
* `sql/0000_preflight.sql`: checks deployed column types/modifiers against the
  migration-derived staging schema; creates a closed `excursion_import` schema.
* `sql/0001_*.sql` through the remaining numbered table chunks: typed staging
  upserts and completion markers, each in its own transaction.
* `sql/9000_apply_atomically.sql`: locks project tables, checks bundle/chunks and
  staging counts, rejects extra target IDs and unknown user triggers, applies all
  28 tables in foreign-key order, verifies exact content, and resets sequences.
* `sql/9001_verify.sql`: returns 28 rows with expected/actual counts, ordered typed
  row MD5 checksums and `ok`; also reports per-user wallet sums, booking price/debt
  totals, and settlement totals. All 28 `ok` values must be true.
* `validation_report.json`: successful disposable-cluster verification results.
* `auth_enrollment.json`, `upload_manifest.json`, `uploads/`: private enrollment
  requests and assets, separate from SQL.

No cloud execution is performed by either command. For a separately authorized
future import, apply the existing migrations first. Use an owner connection with
DDL privileges and RLS bypass. Keep the application and auth enrollment paused
through final application/verification. Submit each complete SQL file, in lexical
order, as one `execute_sql` request; never split a file across sessions or omit
its transaction. Files are UTF-8 and strictly below 145,000 bytes (under 150 KB).
Verify artifact hashes against the report before execution. Stage uploads do not
change working data. A final constraint/schema/trigger error rolls back all target
changes, including trigger state, nullability changes and sequence resets.

Existing target rows with matching primary keys are intentionally overwritten
with this snapshot. Extra target IDs abort instead of being deleted. Unique-key
conflicts with other IDs also abort. The only existing unrelated table,
`public.users`, is never queried or modified by generated SQL. `profiles.auth_user_id`
is excluded from import and checksums, preserving existing enrollment links.
The target is the imported snapshot plus those links, not a concurrent merge.

Each file can be retried. `0000` preserves staging on retry; chunk upserts replace
their own IDs. A bundle fingerprint prevents mixing different exports, migration
versions or timezone choices. To intentionally prepare a different snapshot,
archive the old private artifacts; on the database, first inspect the old staging
schema, then explicitly drop **only** `excursion_import` before starting the new
bundle. The scripts never automatically drop database schemas. After final
verification, archive verification results and optionally remove that staging
schema in a separate authorized step. Keep it until verification is complete.

Only project `set_updated_at` triggers and `bookings.settled_price_changed` are
temporarily disabled inside the final transaction, with trigger function identity
and initial state checks. This preserves original timestamps and settlement
history. Foreign-key/check/unique constraints, RLS, internal triggers and the
accounting lock trigger remain active. Identity sequences use transactional
`ALTER SEQUENCE ... RESTART`, not nontransactional `setval`.

## Source assumptions and compatibility

Column names and types come from current migration CREATE TABLE / ADD COLUMN
statements, never arbitrary export keys. Unexpected columns, tables, secret keys,
missing required fields, duplicate primary keys and orphan foreign keys abort
preparation. Migration and export table sets must contain exactly 28 project
tables. SQL uses quoted JSON literals and `jsonb_to_recordset` with explicit types;
booleans, exact decimals, dates, times, JSON archives and UTC timestamps are
normalized before writing. Absent nullable columns added after the export become
NULL, including the four concession price columns. Archived JSON is decoded as
JSON, preserving nested numeric/boolean/null types rather than a JSON string.

The mirrored Laravel `config/app.php` specifies UTC. Naive legacy timestamps are
therefore interpreted as UTC by default. Confirm the actual exporting database's
timezone convention before a real import; use `--source-timezone` if different.
Existing offset-aware timestamps keep their instants. The current export has
NULL `created_at`/`updated_at` in all 31 schedule templates. To preserve those NULLs,
the final transaction drops NOT NULL **only on those two columns**, without
changing migrations or replacing historical NULLs with fabricated timestamps.
Other constraints remain enforced. The verification uses ordered MD5 checksums
for equality diagnostics; file integrity uses SHA-256.

## Later auth enrollment

The ignored manifest maps each existing profile ID and email to an explicit
`PUT /api/users/:id` request body (`name`, `email`, `role_id`, `color`, `bus_id`,
`password`). It has no bearer token or service credential. Existing legacy
passwords remain private; accounts with missing passwords get 32 random bytes
encoded with `secrets.token_urlsafe(32)` and `requires_password_reset=true`.
Existing generated temporary passwords are reused on regeneration, so rerunning
preparation does not rotate them. Do not print, commit or paste the manifest.
The current snapshot contains 67 profiles: 46 legacy passwords and 21 temporary
passwords requiring reset.

Bootstrap an administrator separately, linking its auth identity to the existing
imported profile by email/ID. Migration `008_auth_management` and API `identity.ts`
appeared during preparation; those files are outside this task's edit scope.
The updated route enrolls unlinked profiles through the Auth admin API using an
identity-operation nonce. Ordinary signup by email alone must not claim a profile.
The bootstrap administrator cannot update its own identity through this route;
exclude that already bootstrapped account from enrollment requests.

The current API requires at least 8 characters, at most 72 UTF-8 bytes and no
control characters. The 21 generated temporary passwords have a fixed prefix
plus 32 random bytes. All 46 available legacy passwords satisfy this policy and
are preserved exactly; no extra passwords are invented or rotated for them.
The manifest's reset flag is an enrollment-workflow requirement; it does not itself
force a Supabase password change. Confirm enforcement separately. API enrollment,
bootstrap, password reset and login behavior are not exercised by the SQL validator.
For ambiguous enrollment failures, reconcile the identity-operation journal before
retrying. Verify each resulting auth link and login separately after bootstrap.
