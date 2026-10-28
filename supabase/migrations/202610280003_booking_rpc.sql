create or replace function public.create_bookings(
  p_excursion_id bigint,
  p_excursion_date date,
  p_time time,
  p_weekday smallint,
  p_stop_id bigint,
  p_seats jsonb,
  p_booked_by bigint default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_profile_id bigint := private.current_profile_id();
  target_profile_id bigint;
  excursion_row public.excursions%rowtype;
  seat_payload jsonb;
  seat_row public.bus_seats%rowtype;
  tariff_row public.excursion_prices%rowtype;
  booking_row public.bookings%rowtype;
  v_seat_number integer;
  v_passenger_type text;
  with_entry boolean;
  ticket_price numeric(10,2);
  debt_amount numeric(10,2);
  slot_limit integer;
  booked_count integer;
  result_rows jsonb := '[]'::jsonb;
begin
  if (select auth.uid()) is null or caller_profile_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if jsonb_typeof(p_seats) <> 'array' or jsonb_array_length(p_seats) = 0 then
    raise exception 'At least one seat is required' using errcode = '22023';
  end if;

  target_profile_id := case
    when p_booked_by is not null and private.is_admin() then p_booked_by
    else caller_profile_id
  end;

  select * into excursion_row
  from public.excursions
  where id = p_excursion_id
  for update;

  if not found or not excursion_row.is_active then
    raise exception 'Excursion is not available' using errcode = 'P0002';
  end if;

  if not exists (select 1 from public.stops where id = p_stop_id) then
    raise exception 'Stop not found' using errcode = 'P0002';
  end if;

  if exists (
    select 1 from public.cancelled_excursion_dates
    where excursion_id = p_excursion_id
      and date_time = (p_excursion_date + p_time) at time zone 'Europe/Moscow'
  ) then
    raise exception 'Excursion is cancelled for this date and time' using errcode = '23514';
  end if;

  select coalesce(max_seats, excursion_row.max_seats) into slot_limit
  from public.excursion_slot_limits
  where excursion_id = p_excursion_id
    and excursion_date = p_excursion_date
    and time = p_time;
  slot_limit := coalesce(slot_limit, excursion_row.max_seats);

  select count(*) into booked_count
  from public.bookings
  where excursion_id = p_excursion_id
    and excursion_date = p_excursion_date
    and time = p_time;

  if booked_count + jsonb_array_length(p_seats) > slot_limit then
    raise exception 'Slot capacity exceeded. Available: %', greatest(0, slot_limit - booked_count)
      using errcode = '23514';
  end if;

  for seat_payload in select value from jsonb_array_elements(p_seats)
  loop
    v_seat_number := (seat_payload ->> 'seat_number')::integer;
    v_passenger_type := seat_payload ->> 'passenger_type';
    with_entry := coalesce((seat_payload ->> 'with_entry')::boolean, false);

    if v_seat_number < 1 or v_seat_number > slot_limit then
      raise exception 'Seat % is outside the slot limit %', v_seat_number, slot_limit
        using errcode = '23514';
    end if;

    if v_passenger_type not in ('adult','child','senior','disabled','special','concession') then
      raise exception 'Unsupported passenger type for seat %', v_seat_number
        using errcode = '23514';
    end if;

    if v_seat_number in (1, 2)
      and not private.is_admin()
      and not exists (
        select 1 from public.seat_permissions
        where excursion_id = p_excursion_id
          and user_id = caller_profile_id
          and excursion_date = p_excursion_date
          and seat_permissions.seat_number = v_seat_number
      )
    then
      raise exception 'Seat % requires administrator permission', v_seat_number
        using errcode = '42501';
    end if;

    select * into seat_row
    from public.bus_seats
    where excursion_id = p_excursion_id
      and bus_seats.seat_number = v_seat_number
    for update;

    if not found then
      raise exception 'Seat % does not exist', v_seat_number using errcode = 'P0002';
    end if;

    if exists (
      select 1 from public.bookings
      where excursion_id = p_excursion_id
        and excursion_date = p_excursion_date
        and time = p_time
        and bus_seat_id = seat_row.id
    ) then
      raise exception 'Seat % is already booked', v_seat_number using errcode = '23505';
    end if;

    select * into tariff_row
    from public.excursion_prices
    where excursion_id = p_excursion_id
      and excursion_prices.passenger_type = v_passenger_type;

    if seat_payload ? 'price' and seat_payload ->> 'price' is not null then
      ticket_price := (seat_payload ->> 'price')::numeric(10,2);
    elsif found then
      ticket_price := case when with_entry
        then coalesce(tariff_row.price_with_entry, tariff_row.price, 0)
        else coalesce(tariff_row.price_without_entry, tariff_row.price, 0)
      end;
    else
      raise exception 'Tariff is not configured for seat %', v_seat_number
        using errcode = '23514';
    end if;

    debt_amount := coalesce((seat_payload ->> 'debt')::numeric(10,2), 0);
    if debt_amount < 0 or debt_amount > ticket_price then
      raise exception 'Invalid debt for seat %', v_seat_number using errcode = '23514';
    end if;
    if coalesce(trim(seat_payload ->> 'customer_name'), '') = ''
      or coalesce(trim(seat_payload ->> 'customer_phone'), '') = '' then
      raise exception 'Customer name and phone are required for seat %', v_seat_number
        using errcode = '23514';
    end if;

    insert into public.bookings (
      excursion_id, weekday, time, excursion_date, bus_seat_id, booked_by,
      price, debt, customer_name, customer_phone, comment, passenger_type,
      with_entry, stop_id
    ) values (
      p_excursion_id, p_weekday, p_time, p_excursion_date, seat_row.id,
      target_profile_id, ticket_price, debt_amount,
      seat_payload ->> 'customer_name', seat_payload ->> 'customer_phone',
      nullif(seat_payload ->> 'comment', ''), v_passenger_type, with_entry, p_stop_id
    ) returning * into booking_row;

    insert into public.wallet_transactions (
      user_id, booking_id, amount, description
    ) values (
      target_profile_id,
      booking_row.id,
      ticket_price - debt_amount,
      format('№%s (%s)', v_seat_number, v_passenger_type)
    );

    update public.bus_seats
    set status = 'booked', booked_by = target_profile_id, booked_at = now()
    where id = seat_row.id;

    result_rows := result_rows || jsonb_build_array(to_jsonb(booking_row));
  end loop;

  return jsonb_build_object('bookings', result_rows);
end;
$$;

create or replace function public.update_booking(
  p_booking_id bigint,
  p_changes jsonb
)
returns public.bookings
language plpgsql
security definer
set search_path = ''
as $$
declare
  booking_row public.bookings%rowtype;
  old_paid numeric(10,2);
  new_paid numeric(10,2);
begin
  select * into booking_row
  from public.bookings
  where id = p_booking_id
  for update;

  if not found then
    raise exception 'Booking not found' using errcode = 'P0002';
  end if;
  if booking_row.booked_by <> private.current_profile_id() and not private.is_admin() then
    raise exception 'Insufficient permissions' using errcode = '42501';
  end if;

  old_paid := booking_row.price - booking_row.debt;

  update public.bookings set
    customer_name = coalesce(p_changes ->> 'customer_name', customer_name),
    customer_phone = coalesce(p_changes ->> 'customer_phone', customer_phone),
    comment = case when p_changes ? 'comment' then nullif(p_changes ->> 'comment', '') else comment end,
    price = case when p_changes ? 'price' then (p_changes ->> 'price')::numeric else price end,
    debt = case when p_changes ? 'debt' then (p_changes ->> 'debt')::numeric else debt end,
    passenger_type = coalesce(p_changes ->> 'passenger_type', passenger_type),
    with_entry = case when p_changes ? 'with_entry' then (p_changes ->> 'with_entry')::boolean else with_entry end,
    stop_id = case when p_changes ? 'stop_id' then (p_changes ->> 'stop_id')::bigint else stop_id end
  where id = p_booking_id
  returning * into booking_row;

  if booking_row.debt < 0 or booking_row.debt > booking_row.price then
    raise exception 'Debt cannot exceed ticket price' using errcode = '23514';
  end if;

  new_paid := booking_row.price - booking_row.debt;
  if new_paid <> old_paid then
    insert into public.wallet_transactions (user_id, booking_id, amount, description)
    values (booking_row.booked_by, booking_row.id, new_paid - old_paid, 'Корректировка бронирования');
  end if;
  return booking_row;
end;
$$;

create or replace function public.cancel_booking(
  p_booking_id bigint,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  booking_row public.bookings%rowtype;
  paid_amount numeric(10,2);
begin
  select * into booking_row
  from public.bookings
  where id = p_booking_id
  for update;

  if not found then
    raise exception 'Booking not found' using errcode = 'P0002';
  end if;
  if booking_row.booked_by <> private.current_profile_id() and not private.is_admin() then
    raise exception 'Insufficient permissions' using errcode = '42501';
  end if;

  paid_amount := booking_row.price - booking_row.debt;
  delete from public.settlement_booking where booking_id = booking_row.id;
  insert into public.wallet_transactions (user_id, booking_id, amount, description)
  values (
    booking_row.booked_by,
    booking_row.id,
    -paid_amount,
    concat('Отмена бронирования', case when p_reason is null then '' else ': ' || p_reason end)
  );
  delete from public.bookings where id = booking_row.id;

  if not exists (
    select 1 from public.bookings
    where bus_seat_id = booking_row.bus_seat_id
  ) then
    update public.bus_seats
    set status = 'available', booked_by = null, booked_at = null
    where id = booking_row.bus_seat_id;
  end if;

  return jsonb_build_object('cancelled_booking_id', p_booking_id);
end;
$$;

revoke all on function public.create_bookings(bigint,date,time,smallint,bigint,jsonb,bigint) from public, anon;
revoke all on function public.update_booking(bigint,jsonb) from public, anon;
revoke all on function public.cancel_booking(bigint,text) from public, anon;
grant execute on function public.create_bookings(bigint,date,time,smallint,bigint,jsonb,bigint) to authenticated;
grant execute on function public.update_booking(bigint,jsonb) to authenticated;
grant execute on function public.cancel_booking(bigint,text) to authenticated;
