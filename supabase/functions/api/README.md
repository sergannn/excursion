# Supabase Flutter compatibility API

Function: `api`. Base URL: `https://<project>.supabase.co/functions/v1/api`;
existing `/api/...` paths work, as do paths without that prefix. Anchored
segments are normalized; encoded separators and repeated slashes fail.

Behavioral authority: exact controllers, models, CreateUserRequest, routes and
ExcursionScheduler under
`/Volumes/ExternalSSD/server_mirrors/77.222.47.218/files/www/excursion.panfilius.ru`.
Migrations 001–003 are unchanged; forward migrations 004–008 add management,
reports, accounting invariants and Auth coordination. Original Laravel and
/Users/servas/booking_krym are untouched. The isolated Flutter admin password
generator and validator match the strong API policy; its success message no
longer implies that a password omitted from a response was unset. For the
additions in 008, Laravel controller/Blade copies are not present inside this
isolated workspace. The PDF contract is verified against
lib/src/data/repositories/bookings_repository.dart and ApiClient array encoding;
exact Laravel ticketPdf/template layout and its extra ids parsing variants are
unverified. No outside Laravel tree was read or modified in this change.

## Configuration and security

Use SUPABASE_URL and SUPABASE_ANON_KEY. Every protected request validates the
Supabase JWT and requires a linked profile. The caller JWT reaches every
query/RPC; roles come from the database. SUPABASE_SERVICE_ROLE_KEY is read only
for POST/PUT/DELETE users after JWT and DB role_id=1 validation. It is used only
for Auth admin create/update/delete, never table reads/writes, ordinary reads,
login or logout. Caller-supplied keys/UUIDs are rejected or ignored. There is no
direct Edge table write. RPCs independently authorize with auth.uid() and fixed
search paths. Private helpers are not client-executable except safe RLS
predicates.

verify_jwt=false permits public reads and OPTIONS to reach the handler;
protected routes authenticate inside the handler. Supplied invalid tokens fail
even on public endpoints. API_ALLOWED_ORIGINS optionally lists exact
comma-separated origins; default *. CORS is not authorization. JSON responses
have no-store, request ID, nosniff and CORS headers. Errors contain message,
error:{code,message}, errors and request_id; never SQL details. Writes require
JSON objects up to 64 KiB. Queries time out after 15 seconds. Ordered pagination
prevents server-cap truncation and fails above 50,000 rows.

## Implemented route matrix

Paths below can omit /api. GET also accepts HEAD, with the same status/headers
and no body. User means a linked authenticated profile; Own/admin restricts
target financial data to the caller or an administrator.

| Method              | Route                                                   | Access      | Envelope and behavior                                                                                   |
| ------------------- | ------------------------------------------------------- | ----------- | ------------------------------------------------------------------------------------------------------- |
| OPTIONS             | any                                                     | Public      | 204 preflight                                                                                           |
| GET                 | /api/app                                                | Public      | data: capability document                                                                               |
| GET                 | /api/auth/me                                            | User        | user, role/profile without credentials                                                                  |
| POST                | /api/auth/login                                         | Public      | email/password to Supabase Auth; legacy token,user; no refresh token or credentials returned            |
| POST                | /api/auth/logout                                        | User        | message; revoke current Auth session with caller JWT and anon key                                       |
| GET                 | /api/schedule                                           | Public      | data: templates with weekday/time entries                                                               |
| GET                 | /api/stops                                              | Public      | stops, ordered                                                                                          |
| GET                 | /api/excursions, /api/excursions/:id                    | Public      | data: expanded occurrences / first matching occurrence                                                  |
| GET                 | /api/excursions/:id/photos                              | User        | data: active private photos, signed URLs for 3600 seconds                                               |
| GET                 | /api/excursions/:id/stops                               | User        | stops, direction order; assigned staff booking stops                                                    |
| GET                 | /api/bookings                                           | User        | bookings: own sales, all for admin, nested excursion/seat/stop/seller                                   |
| GET                 | /api/bookings/driver                                    | Staff/admin | bookings matching own dated/wildcard assignments                                                        |
| POST                | /api/bookings                                           | User        | 201 message,bookings; atomic create_bookings                                                            |
| PUT / DELETE        | /api/bookings/:id                                       | Own/admin   | message,booking / message,cancelled_booking_id; wallet delta/refund and settlement cleanup              |
| GET                 | /api/bookings/:id/ticket-pdf                            | Own/admin   | application/pdf attachment; ids[] multiple tickets, all-or-nothing authorization                        |
| POST                | /api/excursions                                         | Admin       | 201 message,data; template uniqueness, seats and five default tariffs                                   |
| PUT / DELETE        | /api/excursions/:id                                     | Admin       | message,data / message; checked capacity, deletion refunds bookings                                     |
| PUT                 | /api/excursions/:id/prices                              | Admin       | message,data; all six tariffs, commissions and mirrored columns                                         |
| PUT                 | /api/excursions/:id/staff-prices                        | Admin       | message,data; atomic tier replacement                                                                   |
| PUT                 | /api/excursions/:id/actual-amount                       | Admin       | message,data; nullable nonnegative amount                                                               |
| POST / DELETE       | /api/excursions/:id/unscheduled-date[/:dateId]          | Admin       | message,data; 201 create / 200 soft delete                                                              |
| POST                | /api/excursions/:id/cancel-date                         | Admin       | 201 message,cancelled_bookings_count,data; atomic refunds and cleanup                                   |
| DELETE              | /api/excursions/:id/cancel-date/:dateId                 | Admin       | message; restore does not recreate bookings                                                             |
| POST                | /api/excursions/:id/assign                              | Admin       | message,assigned_users,excursion_date,time; scoped replacement, slot limit, automatic driver bus ranges |
| DELETE              | /api/excursions/:id/assign/:userId                      | Admin       | message; removes user pivots and driver ranges                                                          |
| GET                 | /api/excursions/cancelled-dates                         | Admin       | data: title, Moscow date/time and audit fields                                                          |
| GET                 | /api/excursions/check-new-assignments                   | User        | has_new,count,assignments; own, optional last_checked                                                   |
| GET                 | /api/excursions/statistics                              | Admin       | statistics,total_net_profit; whole-excursion revenue, commissions and tiers                             |
| GET                 | /api/buses, /api/buses/:id                              | User        | buses / bus with drivers, search and is_active filters                                                  |
| POST / PUT / DELETE | /api/buses[/:id]                                        | User        | message,bus / message; 201 create, reject deletion with attached drivers                                |
| POST                | /api/buses/:id/assign-driver, /unassign-driver          | User        | message,bus,driver / message; role/bus checks, replaces previous driver                                 |
| POST                | /api/buses/:id/assign-excursion, /unassign-excursion    | User        | 201 message,assignment / 200 message; contiguous partial range allocation, dated driver pivot           |
| GET                 | /api/users, /api/users/:id                              | User        | users,pagination / user; role/search filters, no credentials                                            |
| GET                 | /api/users/roles, /api/roles                            | User        | roles                                                                                                   |
| POST / PUT / DELETE | /api/users[/:id]                                        | Admin       | message,user / message; 201 create; coordinated Auth account and profile changes                        |
| PUT                 | /api/users/:id/color                                    | Admin       | message,user; HEX or null, empty string clears                                                          |
| GET                 | /api/users/:id/assigned-excursions                      | User        | data; normal occurrence expansion and staff restrictions                                                |
| GET                 | /api/users/:id/wallet                                   | Own/admin   | user,balance,transactions                                                                               |
| GET                 | /api/users/:id/sales                                    | Own/admin   | user,total_sales,bookings with resolved occurrence dates                                                |
| GET                 | /api/users/:id/profit                                   | Own/admin   | user,total_profit,breakdown,totals_by_type; per-ticket rounding, partner rate                           |
| GET                 | /api/users/:id/staff-profit                             | Own/admin   | total_profit,breakdown; slot tiers, driver gets guide pay when no guide                                 |
| GET / POST / DELETE | /api/seat-permissions[/:id]                             | Admin       | permissions / 201 message,permission / message; seats 1–2                                               |
| GET                 | /api/seat-permissions/check                             | User        | has_permission_for_seat_1,has_permission_for_seat_2,permissions; own grants, excursion_id/date required |
| GET                 | /api/seat-access-requests                               | Admin       | requests; optional status filter                                                                        |
| GET / POST          | /api/seat-access-requests/my, /api/seat-access-requests | User        | requests / 201 message,request; own, one pending per natural key                                        |
| POST                | /api/seat-access-requests/:id/approve, /reject          | Admin       | message; pending-only transition, reviewer audit, atomic approval/grant                                 |
| GET                 | /api/settlements, /api/settlements/seller/:sellerId     | Own/admin   | settlements with seller and booking counts                                                              |
| GET                 | /api/settlements/sellers                                | User        | sellers with RLS-visible bookings                                                                       |
| GET                 | /api/settlements/sellers/:sellerId/sales                | Own/admin   | seller,total_amount,sales,period_stats; date_from/date_to/settled filters                               |
| GET                 | /api/settlements/sellers/:sellerId/calendar-status      | Own/admin   | days_status: settled/unsettled/partial keyed by Moscow date                                             |
| POST                | /api/settlements                                        | Own/admin   | 201 message,settlement; exclusive membership, gross ticket-price total                                  |
| DELETE              | /api/settlements/:id                                    | Own/admin   | message; detach bookings without wallet change                                                          |
| POST                | /api/settlements/:id/remove-booking                     | Own/admin   | message,settlement_deleted; recalculate or delete empty sheet                                           |

No production inventory route intentionally returns 501. Development-only
/api/test, /api/roles-test, /api/test-ids-parsing and /api/test-seating-data
return 404. Unknown paths return 404; unsupported verbs 405. The mirror does not
define excursion PUT/DELETE or user PUT; these are explicit admin extensions.

## Input and occurrence semantics

Booking POST requires excursion_id, excursion_date (real YYYY-MM-DD), time
(HH:mm or HH:mm:00), stop_id and seats. Legacy seat_numbers/passenger_type
works. Per-seat customer fields override top-level fields. Only admins may set
another booked_by_id. Omitted price selects SQL tariffs. Duplicate seats,
invalid debt and mismatched weekdays fail. PUT allows
customer_name/customer_phone/comment/
passenger_type/with_entry/price/debt/stop_id. stop_id:null fails: schema
requires a stop. DELETE requires a nonempty reason.

Excursion create requires schedule_template_id, title, price, max_seats (1–100);
description/direction/is_active are optional. Prices PUT requires all six types
in prices, each with price and both commission percentages (0–100); entry prices
default to price when null/omitted. Staff prices PUT requires staff_prices
array. Assign requires assignments array (empty clears), optional
excursion_date/time/ slot_max_seats; manual_amount is nullable nonnegative pay.
Bus create/update requires number and capacity. Settlement create requires
seller_id and nonempty unique booking_ids; notes/date_from/date_to are optional.

Excursion filters: status=upcoming|past|all (default upcoming), include_past,
date, time, weekday=1..7, assigned_to, include_booking_details. Window is today
through 29 days ahead, plus 30 days back for past/all. Extra dates are
deduplicated; cancelled slots remain visible; soft-deleted dates are omitted.
Moscow +03:00 wall times apply. Staff see own dated/wildcard assignments. Detail
without slot selects the first matching occurrence.

RLS hides other sellers' customers. Exact per-slot occupancy is available only
to admins and assigned staff. Others get occupancy_complete=false, null
booked/available counts and visible_booked_seats_count. Globally occupied seats
with unknown slot remain reserved/occupancy_known=false. Public reads omit
seats. Flutter currently displays null counts/balances as zero; that UI
limitation remains. Another user's hidden balance is null/balance_visible=false.
Hidden inactive nested excursions have an explicit unavailable placeholder.

## Auth boundary and deliberate safety differences

User POST requires name,email,role_id,password (optional color/bus_id). PUT
accepts partial profile fields and optional password reset, including password
alone. Email edits also change Auth login email; numeric profile IDs are
retained. Updating an imported unlinked profile enrolls Auth and requires a
password. Passwords require 8+ characters, at most 72 UTF-8 bytes and no control
characters; empty/null passwords fail. This keeps existing imported credentials
compatible while enforcing Supabase Auth's technical limit. Credentials are
never stored in profiles/journal, returned or logged. Admin creation confirms
email (the administrator is trusted to verify it); there is no public role
assignment. DELETE removes Auth then profile; self mutations, administrator
deletion and financial-history deletion fail. Self changes use a separate
trusted workflow.

begin_identity_operation runs with caller JWT, rechecks admin, locks/stages the
profile and stores a private durable journal without secrets. Pending targets
are hidden by a restrictive profile RLS policy and lose domain identity/role.
Concurrent identity/color changes conflict. The Auth trigger accepts an existing
profile only with the operation nonce supplied by the admin API, preventing
email-based profile takeover during ordinary signup. finish_identity_operation
checks Auth linkage/email or Auth absence, then commits/deletes the journal.
Direct manage_user CRUD is disabled; color remains available via its admin RPC.
Auth 4xx failures compensate profile staging. Auth/network/5xx ambiguity or
failed finalization returns 503 identity_operation_pending with an operation ID;
target access remains blocked. Preparation transport ambiguity also reports its
preallocated operation ID. Never blindly retry: an Auth operation may have run.
No automatic journal expiry discards uncertain state.

Reconciliation is an administrator/operator task: inspect
private.identity_operations and the corresponding Auth user in a trusted
local/operator context. If Auth succeeded, finish with commit_change=true using
the original admin JWT; if it failed, restore Auth first as needed and finish
with false. A created Auth account must be removed before rolling back a create.
If the original admin loses access, a trusted DB operator must reconcile;
journals never become client-readable. Auth deletion cannot be undone with the
same UUID, and password hashes cannot be recovered: completed Auth changes are
finalized, not blindly reversed. Auth API and Postgres cannot share one
distributed transaction; interruption therefore requires explicit
reconciliation. Storage-owned Auth users can reject deletion; their profile is
restored on a definite rejection.

Login returns only the access JWT in legacy token,user. It expires according to
Supabase project policy; legacy clients must log in again after expiration.
Logout revokes the current session/refresh tokens; an already-issued access JWT
may remain valid until expiry (Supabase behavior), so this is not Sanctum's
immediate token revocation guarantee. No service key is needed for logout.

PDF accepts ids[]=1&ids[]=2, indexed ids[0], and repeated ids; absent ids uses
the path ID. Empty/malformed IDs fail 422, duplicates are removed, maximum 100
IDs. The path booking is authorized even when ids overrides the rendered set.
Every selected booking must be owned by the caller or caller must be admin;
hidden/missing/other-owner resources all fail 404 without partial PDFs. Assigned
staff do not gain PDF access to another seller's customer. Each booking gets a
separate ticket page (long fields wrap onto continuation pages). It includes
excursion/date/time, stop, seat, passenger type, customer, seller, price, paid
and debt; internal notes, phone/email of seller and unrelated customers are
omitted. The embedded font is DejaVu Sans from the existing mislabeled Roboto
asset; fonts/LICENSE.txt retains the font's redistribution license. It is
packaged as base64 text to keep patch-based changes reviewable. config.toml
includes static font assets; there are no runtime font downloads. Unsupported
glyphs become ?.

Own/admin financial RLS boundaries remain; Laravel's unrestricted cross-user
financial access is narrowed. Bus mutations retain Laravel authenticated-user
access. Staff report contexts expose only aggregates across sellers, never other
sellers' customer PII. WalletController.staffProfit uses tiers rather than
stored manual_amount; this is retained. Statistics use whole-excursion counts
and seller commission rates, including partner sales; actual_amount and the
staff-report automatic-guide rule do not alter statistics.

Cancellation refunds price-debt, preserving migration 003's collected-money
ledger. Laravel cancelDate subtracts the full price and can refund unpaid debt;
that inconsistency is corrected. Settlements mark sales without wallet changes.
Totals equal current member ticket prices, including edits/cancellation; empty
sheets disappear. Accounting locks precede row locks in booking/settlement RPCs.
Excursion locks serialize capacity/cancellation/allocation with booking
creation. Existing duplicate membership fails migration 004 explicitly; no
financial data is discarded. NOT VALID price/pay checks preserve old rows while
enforcing every new insert/update.

## Local verification — no deployment

From this directory:

```sh
deno task fmt:check
deno task lint
deno task check
deno task test
```

Deno tests use fake HTTP transport with the real Supabase client: inventory
coverage without production 501 exceptions, every mutation RPC contract, error
mapping, auth forwarding, financial calculations, validation, legacy envelopes,
schedule expansion, hidden data, pagination, CORS and HEAD.

SQL integration: in a fresh disposable local PostgreSQL database, apply
supabase/tests/bootstrap.sql, migrations 001–011 in order, then
supabase/tests/invariants.sql with psql -v ON_ERROR_STOP=1. Bootstrap creates
minimal Auth/Storage surfaces; never run it against a project database. Tests
use the authenticated database role and simulated auth.uid(), and roll back
fixtures. They verify authorization/unlinked identities, tariff mirroring,
invalid replacement rollback, seats/allocation, profiles/color, requests,
aggregate reports, refunds, settlement recalculation, identity
staging/compensation, RLS pending denial and Auth trigger linking. Auth tests
use the real Supabase JS client with fake HTTP transport and assert service-key
scoping. PDF tests parse real generated documents, embedded TrueType/Unicode
resources and owner checks.

The cloud deployment was additionally verified against project
`bmyvbcnoeaacvklyijia`: all 67 imported logins succeeded, 10 representative API
sections returned HTTP 200, all 32 active photo records produced signed URLs,
and a live imported booking produced a one-page Cyrillic A4 PDF. The original
Laravel deployment remains unchanged.
