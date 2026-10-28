create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

create or replace function private.current_profile_id()
returns bigint
language sql
stable
security definer
set search_path = ''
as $$
  select id from public.profiles where auth_user_id = (select auth.uid())
$$;

create or replace function private.current_role_id()
returns bigint
language sql
stable
security definer
set search_path = ''
as $$
  select role_id from public.profiles where auth_user_id = (select auth.uid())
$$;

create or replace function private.is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((select private.current_role_id()) = 1, false)
$$;

create or replace function private.is_assigned_staff(
  target_excursion_id bigint,
  target_date date,
  target_time time
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.excursion_user eu
    where eu.user_id = (select private.current_profile_id())
      and eu.excursion_id = target_excursion_id
      and (eu.excursion_date is null or eu.excursion_date = target_date)
      and (eu.time is null or eu.time = to_char(target_time, 'HH24:MI'))
  )
$$;

grant usage on schema public to anon, authenticated;

-- Keep permissions on pre-existing public objects (notably public.users)
-- untouched. Only the tables created by this project are restricted here.
do $$
declare
  table_name text;
  sequence_name text;
begin
  foreach table_name in array array[
    'app_roles','buses','profiles','schedule_templates','schedule_days',
    'excursions','stops','excursion_prices','staff_prices','bus_seats',
    'bookings','wallet_transactions','excursion_user',
    'excursion_bus_assignments','excursion_bus_stop_assignments',
    'excursion_bus_booking_assignments','seat_permissions',
    'seat_access_requests','settlements','settlement_booking',
    'unscheduled_excursion_dates','cancelled_excursion_dates',
    'excursion_photos','excursion_slot_limits','excursion_statement_entries',
    'demo_booking_requests','archived_excursions','archived_bookings'
  ]
  loop
    execute format(
      'revoke all on table public.%I from anon, authenticated',
      table_name
    );

    sequence_name := pg_get_serial_sequence('public.' || table_name, 'id');
    if sequence_name is not null then
      execute format(
        'revoke all on sequence %s from anon, authenticated',
        sequence_name
      );
    end if;
  end loop;
end;
$$;

grant select on public.schedule_templates, public.schedule_days,
  public.excursions, public.stops, public.excursion_prices,
  public.unscheduled_excursion_dates, public.cancelled_excursion_dates,
  public.excursion_photos to anon, authenticated;

grant select on public.app_roles, public.profiles, public.buses,
  public.staff_prices, public.bus_seats, public.excursion_user,
  public.excursion_bus_assignments, public.excursion_bus_stop_assignments,
  public.excursion_bus_booking_assignments, public.excursion_slot_limits
  to authenticated;

grant select on public.bookings, public.wallet_transactions,
  public.seat_permissions, public.seat_access_requests,
  public.settlements, public.settlement_booking,
  public.excursion_statement_entries to authenticated;

grant insert on public.seat_access_requests to authenticated;

do $$
declare
  table_name text;
  sequence_name text;
begin
  foreach table_name in array array[
    'app_roles','buses','profiles','schedule_templates','schedule_days',
    'excursions','stops','excursion_prices','staff_prices','bus_seats',
    'bookings','wallet_transactions','excursion_user',
    'excursion_bus_assignments','excursion_bus_stop_assignments',
    'excursion_bus_booking_assignments','seat_permissions',
    'seat_access_requests','settlements','settlement_booking',
    'unscheduled_excursion_dates','cancelled_excursion_dates',
    'excursion_photos','excursion_slot_limits','excursion_statement_entries',
    'demo_booking_requests','archived_excursions','archived_bookings'
  ]
  loop
    sequence_name := pg_get_serial_sequence('public.' || table_name, 'id');
    if sequence_name is not null then
      execute format(
        'grant usage, select on sequence %s to authenticated',
        sequence_name
      );
    end if;
  end loop;
end;
$$;

do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'app_roles','buses','profiles','schedule_templates','schedule_days',
    'excursions','stops','excursion_prices','staff_prices','bus_seats',
    'bookings','wallet_transactions','excursion_user',
    'excursion_bus_assignments','excursion_bus_stop_assignments',
    'excursion_bus_booking_assignments','seat_permissions',
    'seat_access_requests','settlements','settlement_booking',
    'unscheduled_excursion_dates','cancelled_excursion_dates',
    'excursion_photos','excursion_slot_limits','excursion_statement_entries',
    'demo_booking_requests','archived_excursions','archived_bookings'
  ]
  loop
    execute format('alter table public.%I enable row level security', table_name);
  end loop;
end;
$$;

create policy public_read_schedule_templates on public.schedule_templates
  for select to anon, authenticated using (true);
create policy public_read_schedule_days on public.schedule_days
  for select to anon, authenticated using (true);
create policy public_read_excursions on public.excursions
  for select to anon, authenticated using (is_active or (select private.is_admin()));
create policy public_read_stops on public.stops
  for select to anon, authenticated using (true);
create policy public_read_excursion_prices on public.excursion_prices
  for select to anon, authenticated using (true);
create policy public_read_unscheduled_dates on public.unscheduled_excursion_dates
  for select to anon, authenticated using (deleted_at is null or (select private.is_admin()));
create policy public_read_cancelled_dates on public.cancelled_excursion_dates
  for select to anon, authenticated using (true);
create policy public_read_excursion_photos on public.excursion_photos
  for select to anon, authenticated using (is_active or (select private.is_admin()));

create policy authenticated_read_roles on public.app_roles
  for select to authenticated using (true);
create policy authenticated_read_profiles on public.profiles
  for select to authenticated using (true);
create policy authenticated_read_buses on public.buses
  for select to authenticated using (true);
create policy authenticated_read_staff_prices on public.staff_prices
  for select to authenticated using (true);
create policy authenticated_read_bus_seats on public.bus_seats
  for select to authenticated using (true);
create policy authenticated_read_assignments on public.excursion_user
  for select to authenticated using (true);
create policy authenticated_read_bus_assignments on public.excursion_bus_assignments
  for select to authenticated using (true);
create policy authenticated_read_stop_assignments on public.excursion_bus_stop_assignments
  for select to authenticated using (true);
create policy authenticated_read_booking_assignments on public.excursion_bus_booking_assignments
  for select to authenticated using (true);
create policy authenticated_read_slot_limits on public.excursion_slot_limits
  for select to authenticated using (true);

create policy users_read_authorized_bookings on public.bookings
  for select to authenticated
  using (
    booked_by = (select private.current_profile_id())
    or (select private.is_admin())
    or private.is_assigned_staff(excursion_id, excursion_date, time)
  );

create policy users_read_own_wallet on public.wallet_transactions
  for select to authenticated
  using (user_id = (select private.current_profile_id()) or (select private.is_admin()));

create policy users_read_own_permissions on public.seat_permissions
  for select to authenticated
  using (user_id = (select private.current_profile_id()) or (select private.is_admin()));

create policy users_read_own_access_requests on public.seat_access_requests
  for select to authenticated
  using (user_id = (select private.current_profile_id()) or (select private.is_admin()));
create policy users_create_own_access_requests on public.seat_access_requests
  for insert to authenticated
  with check (
    user_id = (select private.current_profile_id())
    and status = 'pending'
    and reviewed_by is null
    and reviewed_at is null
  );

create policy users_read_own_settlements on public.settlements
  for select to authenticated
  using (seller_id = (select private.current_profile_id()) or (select private.is_admin()));
create policy users_read_own_settlement_bookings on public.settlement_booking
  for select to authenticated
  using (
    (select private.is_admin())
    or exists (
      select 1 from public.settlements s
      where s.id = settlement_id
        and s.seller_id = (select private.current_profile_id())
    )
  );

create policy admins_read_statement_entries on public.excursion_statement_entries
  for select to authenticated using ((select private.is_admin()));

do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'app_roles','buses','profiles','schedule_templates','schedule_days',
    'excursions','stops','excursion_prices','staff_prices','bus_seats',
    'bookings','wallet_transactions','excursion_user',
    'excursion_bus_assignments','excursion_bus_stop_assignments',
    'excursion_bus_booking_assignments','seat_permissions',
    'seat_access_requests','settlements','settlement_booking',
    'unscheduled_excursion_dates','cancelled_excursion_dates',
    'excursion_photos','excursion_slot_limits','excursion_statement_entries',
    'demo_booking_requests','archived_excursions','archived_bookings'
  ]
  loop
    execute format(
      'create policy %I on public.%I for all to authenticated '
      'using ((select private.is_admin())) with check ((select private.is_admin()))',
      'admins_manage_' || table_name,
      table_name
    );
  end loop;
end;
$$;

create or replace function private.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (auth_user_id, role_id, email, name)
  values (
    new.id,
    2,
    new.email,
    coalesce(new.raw_user_meta_data ->> 'name', split_part(new.email, '@', 1))
  )
  on conflict (email) do update set auth_user_id = excluded.auth_user_id;
  return new;
end;
$$;

create trigger on_auth_user_created_excursion
  after insert on auth.users
  for each row execute function private.handle_new_auth_user();

insert into storage.buckets (id, name, public)
values ('excursion-photos', 'excursion-photos', false)
on conflict (id) do update set public = excluded.public;

create policy authenticated_read_excursion_photo_objects on storage.objects
  for select to authenticated
  using (bucket_id = 'excursion-photos');
create policy admins_manage_excursion_photo_objects on storage.objects
  for all to authenticated
  using (bucket_id = 'excursion-photos' and (select private.is_admin()))
  with check (bucket_id = 'excursion-photos' and (select private.is_admin()));
