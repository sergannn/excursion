# Excursion Supabase migration audit

This directory is an isolated copy of the excursion Flutter application. The
Laravel production application and its MySQL database are not modified.

## Inventory

- 166 Laravel routes in total; 70 routes are under `/api`.
- 25 Eloquent models and 9 API controllers.
- 42 MySQL tables in the current database. Twenty-eight contain application
  domain data; the remainder are Laravel cache, queue, session, Sanctum, and
  Telescope infrastructure.
- The largest controllers are `ExcursionController` (1541 lines),
  `BookingController` (1148), `BusController` (554),
  `SettlementController` (479), and `WalletController` (388).
- The API contract snapshot is in `docs/laravel-api-endpoints.tsv`.
- The source MySQL domain schema is in
  `docs/mysql-domain-schema-reference.sql`.

## Target architecture

| Existing responsibility | Supabase replacement |
| --- | --- |
| Laravel Sanctum | Supabase Auth |
| `moonshine_users` | `profiles` linked to `auth.users` |
| MySQL domain tables | PostgreSQL tables in `public` |
| Controller authorization | grants plus RLS policies |
| Multi-table booking writes | PostgreSQL RPC functions |
| Excursion photos | Supabase Storage bucket `excursion-photos` |
| Polling for changed bookings | Supabase Realtime after parity is proven |
| Ticket PDF and complex HTTP responses | Edge Function `api` |
| MoonShine administration | Flutter admin screens initially; a separate admin UI later |

## Endpoint groups

| Group | Routes | Migration strategy |
| --- | ---: | --- |
| Auth | 3 | Supabase Auth and profile lookup |
| Bookings | 6 | RPC for create/update/cancel; Edge Function for PDF |
| Buses | 9 | PostgREST reads and admin RPC writes |
| Excursions and schedule | 18 | views for reads; admin RPC writes |
| Seat permissions and requests | 9 | RLS plus admin review RPC |
| Settlements | 8 | financial RPC functions only |
| Users and wallet | 11 | profiles plus protected views/RPC |
| Stops | 1 | public read-only PostgREST |
| Development-only routes | 5 | intentionally not migrated |

## Domain tables

The Supabase migration retains numeric legacy IDs so existing foreign keys and
Flutter JSON models remain stable. `profiles.auth_user_id` is the bridge to the
UUID used by Supabase Auth. Plain-text passwords, Sanctum tokens, sessions,
Laravel jobs/cache, and Telescope data are explicitly excluded.

## Security boundary

Public users may only read active excursion catalogue data, schedules, stops,
prices, and active photos. Authenticated users can read shared operational data
needed by the application. Seller-owned bookings and financial rows are limited
by RLS. Administrative writes and every operation that changes multiple tables
must go through a checked RPC or Edge Function. The service-role key must never
be shipped in Flutter.

## Migration phases

1. Apply schema, constraints, grants, and RLS to a new Supabase project.
2. Import roles and profiles, create Auth users, then import reference data.
3. Import transactional data in dependency order and reset identity sequences.
4. Port authentication and read-only repositories in Flutter.
5. Port booking lifecycle and wallet calculations to tested RPC functions.
6. Port assignments, permissions, settlements, photos, and ticket PDF.
7. Run contract tests against Laravel and Supabase using the same fixtures.
8. Only after parity, perform a fresh production export and controlled cutover.

## Configuration

No project URL or key is committed. Run the copy with:

```sh
flutter run \
  --dart-define=SUPABASE_URL=https://PROJECT.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLISHABLE_KEY
```
