-- Booking::excursion_date accessor, with Moscow wall-time semantics. Weekly
-- legacy bookings resolve to the nearest ISO weekday, then booked_at fallback.
create policy assigned_staff_read_inactive_excursions on public.excursions
for select to authenticated using (exists(select 1 from public.excursion_user a
  where a.excursion_id=excursions.id and a.user_id=(select private.current_profile_id())));
create function private.booking_datetime(b public.bookings, e public.excursions)
returns timestamptz language sql stable set search_path = '' as $$
  select case when b.excursion_date is not null then
    (b.excursion_date+coalesce(b.time,'00:00'::time)) at time zone 'Europe/Moscow'
  when e.date_time is not null then e.date_time
  when b.weekday is not null and b.time is not null then
    (((now() at time zone 'Europe/Moscow')::date +
    ((b.weekday-extract(isodow from now() at time zone 'Europe/Moscow')::int+7)%7)) + b.time) at time zone 'Europe/Moscow'
  else b.booked_at end
$$;

-- Definer read is needed to count all passengers for an assigned staff member.
-- It returns only aggregates for other sellers, never their customer PII.
create function public.financial_context(target_id bigint)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare u public.profiles; result jsonb;
begin
  if private.current_profile_id() is null or (target_id<>private.current_profile_id() and not private.is_admin()) then
    raise exception 'Own financial reports only' using errcode='42501'; end if;
  select * into u from public.profiles where id=target_id;
  if not found then raise exception 'User not found' using errcode='P0002'; end if;
  select jsonb_build_object(
    'user',jsonb_build_object('id',u.id,'name',u.name,'email',u.email,'role_id',u.role_id,
      'role',(select name from public.app_roles where id=u.role_id),'is_partner',u.role_id=4),
    'bookings',coalesce((select jsonb_agg(to_jsonb(b) || jsonb_build_object('excursion',to_jsonb(e),
      'resolved_date_time',private.booking_datetime(b,e),'stop',(select to_jsonb(s) from public.stops s where s.id=b.stop_id)) order by b.created_at desc,b.id desc)
      from public.bookings b join public.excursions e on e.id=b.excursion_id where b.booked_by=target_id),'[]'::jsonb),
    'transactions',coalesce((select jsonb_agg(w order by w.created_at desc,w.id desc) from public.wallet_transactions w where w.user_id=target_id),'[]'::jsonb),
    'prices',coalesce((select jsonb_agg(p) from public.excursion_prices p where exists(select 1 from public.bookings b where b.excursion_id=p.excursion_id and b.booked_by=target_id)),'[]'::jsonb),
    'staff_prices',coalesce((select jsonb_agg(p order by p.id) from public.staff_prices p where exists(select 1 from public.excursion_user a where a.excursion_id=p.excursion_id and a.user_id=target_id)),'[]'::jsonb),
    'assignments',coalesce((select jsonb_agg(a order by a.id) from public.excursion_user a where exists(select 1 from public.excursion_user mine where mine.excursion_id=a.excursion_id and mine.user_id=target_id)),'[]'::jsonb),
    'staff_slots',coalesce((select jsonb_agg(x) from (
      select e.id excursion_id,e.title excursion_title,
        to_char(private.booking_datetime(b,e) at time zone 'Europe/Moscow','YYYY-MM-DD') excursion_date,
        to_char(private.booking_datetime(b,e) at time zone 'Europe/Moscow','HH24:MI') time,
        private.booking_datetime(b,e) date_time,count(*) passenger_count,sum(b.price) total_revenue,
        jsonb_build_object('adult',count(*) filter(where b.passenger_type='adult'),
          'child',count(*) filter(where b.passenger_type='child'),'senior',count(*) filter(where b.passenger_type='senior'),
          'disabled',count(*) filter(where b.passenger_type='disabled'),'special',count(*) filter(where b.passenger_type='special'),
          'concession',count(*) filter(where b.passenger_type='concession')) passengers_by_type
      from public.bookings b join public.excursions e on e.id=b.excursion_id
      where e.is_active and exists(select 1 from public.excursion_user a where a.excursion_id=e.id and a.user_id=target_id
        and (a.excursion_date is null or a.excursion_date=(private.booking_datetime(b,e) at time zone 'Europe/Moscow')::date)
        and (a.time is null or a.time=to_char(private.booking_datetime(b,e) at time zone 'Europe/Moscow','HH24:MI')))
      group by e.id,private.booking_datetime(b,e) order by private.booking_datetime(b,e) desc,e.id
    ) x),'[]'::jsonb)) into result;
  return result;
end $$;

revoke all on function public.financial_context(bigint) from public,anon;
grant execute on function public.financial_context(bigint) to authenticated;
revoke all on all functions in schema private from public,anon,authenticated;
comment on function public.financial_context(bigint) is
  'Own/admin reports. Staff receive passenger aggregates across sellers, never other sellers customer details. Commission and staff tiers follow WalletController; manual_amount is stored by assignment but is not used by that controller.';
comment on function public.manage_settlement(text,bigint,jsonb) is
  'Exclusive booking membership and atomic total=sum(ticket price). Marking settled does not change wallet. Empty settlements disappear; booking cancellation and price edits maintain totals.';
comment on function public.manage_excursion(text,bigint,bigint,jsonb) is
  'Admin only. Excursion lock serializes capacity, cancellation and allocation with create_bookings. Cancellation refunds price-debt to preserve the collected-money ledger; restore does not recreate bookings.';
