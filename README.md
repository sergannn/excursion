# Excursion booking — isolated Supabase migration

The compatibility API implements the production routes, including Auth account
management and Cyrillic ticket PDFs, from the
[Laravel inventory](docs/laravel-api-endpoints.tsv). The
[API matrix](supabase/functions/api/README.md) documents routes, authorization,
response envelopes and the Supabase Auth boundary.

Migrations 001–003 are preserved. Forward migrations 004–007 add transactional
management RPCs, reports and booking/settlement ledger invariants. Migration 008
adds coordinated Auth/profile operations with a durable compensation journal.
Migrations 009–011 preserve non-email legacy logins through internal Auth aliases
and grant linked users access to ready profiles.
Domain requests use the anonymous project key and caller JWT. Only validated
admin identity mutations use the service key, exclusively for Auth admin calls.

The isolated copy is deployed to Supabase project `bmyvbcnoeaacvklyijia`:

* 28 domain tables and 4,890 source rows are imported;
* all 67 profiles are linked to Supabase Auth;
* 8 unique Storage objects back 32 excursion-photo records;
* Edge Function `api` serves the Laravel-compatible routes and A4 ticket PDFs.

The source Laravel installation is not modified or redirected. Build Flutter
with the project URL and a publishable key rather than committing credentials:

```sh
flutter build web --release \
  --dart-define=SUPABASE_URL=https://bmyvbcnoeaacvklyijia.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_...
```

Run `deno task fmt:check`, `deno task lint`, `deno task check`, `deno task test`
from `supabase/functions/api`. Local SQL tests and disposable database setup are
documented in the API README.

Private exports, passwords, generated import SQL and copied customer photos live
under ignored `supabase/.private_import/`. Signing keys, build output and generated
Fastlane reports are also ignored and must never be committed.
