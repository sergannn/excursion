-- Bus mutations are available to authenticated profiles as in BusController.
-- User administration is restricted to admins: the old public role/password
-- creation endpoint must not become a Supabase privilege-escalation endpoint.
create function public.manage_bus(action text, target_id bigint default null, payload jsonb default '{}')
returns jsonb language plpgsql security definer set search_path = '' as $$
declare result jsonb; b public.buses; u public.profiles; a public.excursion_bus_assignments;
  eid bigint:=(payload->>'excursion_id')::bigint; d date:=(payload->>'excursion_date')::date; tm text:=payload->>'time';
begin
  if private.current_profile_id() is null then raise exception 'Authentication required' using errcode='42501'; end if;
  -- Same order as excursion assignment: excursion, bus, driver. The excursion
  -- lock serializes range allocation with booking/capacity/cancellation writes.
  if eid is not null then
    perform 1 from public.excursions where id=eid for update;
    if not found then raise exception 'Excursion not found' using errcode='P0002'; end if;
  end if;
  if action='create' then
    if payload->>'number' is null or payload->>'capacity' is null then raise exception 'Number/capacity required' using errcode='22023'; end if;
    result:=private.write_fields('buses',null,payload,array['number','model','capacity','license_plate','is_active']);
  else
    select * into b from public.buses where id=target_id for update;
    if not found then raise exception 'Bus not found' using errcode='P0002'; end if;
    case action
    when 'update' then
      if payload->>'number' is null or payload->>'capacity' is null then raise exception 'Number/capacity required' using errcode='22023'; end if;
      result:=private.write_fields('buses',target_id,payload,array['number','model','capacity','license_plate','is_active']);
    when 'delete' then
      if exists(select 1 from public.profiles where bus_id=target_id) then raise exception 'Bus has drivers' using errcode='23514'; end if;
      delete from public.buses where id=target_id;
      return jsonb_build_object('message','Автобус успешно удален');
    when 'assign-driver','unassign-driver' then
      select * into u from public.profiles where id=(payload->>'driver_id')::bigint for update;
      if not found then raise exception 'Driver not found' using errcode='P0002'; end if;
      if action='assign-driver' then
        if u.role_id<>3 then raise exception 'Not a driver' using errcode='22023'; end if;
        update public.profiles set bus_id=null where bus_id=target_id;
        update public.profiles set bus_id=target_id where id=u.id;
        return jsonb_build_object('message','Автобус успешно привязан к водителю','bus',jsonb_build_object('id',b.id,'number',b.number),
          'driver',jsonb_build_object('id',u.id,'name',u.name,'email',u.email));
      else
        if u.bus_id is distinct from target_id then raise exception 'Driver not assigned to bus' using errcode='22023'; end if;
        update public.profiles set bus_id=null where id=u.id;
      end if;
    when 'assign-excursion' then
      result:=private.allocate_bus(eid,target_id,(payload->>'driver_id')::bigint,d,tm);
      return jsonb_build_object('message','Автобус назначен на экскурсию','assignment',result);
    when 'unassign-excursion' then
      select * into a from public.excursion_bus_assignments where bus_id=target_id and excursion_id=eid and excursion_date=d and time=tm for update;
      if not found then raise exception 'Assignment not found' using errcode='P0002'; end if;
      delete from public.excursion_user where excursion_id=eid and user_id=a.driver_id and role_in_excursion='driver' and excursion_date=d and time=tm;
      delete from public.excursion_bus_assignments where id=a.id;
    else raise exception 'Unknown action' using errcode='22023';
    end case;
  end if;
  if result is not null then
    if trim(result->>'number')='' or length(result->>'number')>255 then raise exception 'Invalid number' using errcode='22023'; end if;
    return jsonb_build_object('message','Автобус сохранен','bus',result);
  end if;
  return jsonb_build_object('message','Автобус отвязан');
end $$;

create function public.manage_user(action text, target_id bigint default null, payload jsonb default '{}')
returns jsonb language plpgsql security definer set search_path = '' as $$
declare result jsonb; u public.profiles; role_name text;
begin
  perform private.require_admin();
  if action='create' then
    result:=private.write_fields('profiles',null,payload,array['name','email','role_id','color','bus_id']);
  else
    select * into u from public.profiles where id=target_id for update;
    if not found then raise exception 'User not found' using errcode='P0002'; end if;
    if action='delete' then
      if target_id=private.current_profile_id() then raise exception 'Cannot delete current user' using errcode='22023'; end if;
      if u.role_id=1 then raise exception 'Cannot delete administrator' using errcode='42501'; end if;
      -- Historical financial ownership is retained. FK RESTRICT rejects deletion
      -- with live bookings, wallet or settlements rather than losing the ledger.
      delete from public.profiles where id=target_id;
      return jsonb_build_object('message','Пользователь удалён');
    elsif action='color' then
      result:=private.write_fields('profiles',target_id,payload,array['color']);
    elsif action='update' then
      result:=private.write_fields('profiles',target_id,payload,array['name','email','role_id','color','bus_id']);
    else raise exception 'Unknown action' using errcode='22023'; end if;
  end if;
  if length(result->>'name') not between 2 and 255 or length(result->>'email')>190 or result->>'email' !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then
    raise exception 'Invalid name/email' using errcode='22023'; end if;
  select name into role_name from public.app_roles where id=(result->>'role_id')::bigint;
  return jsonb_build_object('message','Пользователь сохранен','user',(result-'auth_user_id') || jsonb_build_object('role',role_name));
end $$;

-- One pending request per natural key, including callers bypassing Edge.
-- Serializing on the excursion also works for existing installations that may
-- contain duplicate pending requests; do not destroy such data in a migration.
create function public.manage_seat_access(action text, target_id bigint default null, payload jsonb default '{}')
returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid bigint:=private.current_profile_id(); r public.seat_access_requests; result jsonb;
begin
  if uid is null then raise exception 'Authentication required' using errcode='42501'; end if;
  if action<>'request' then perform private.require_admin(); end if;
  case action
  when 'permission','request' then
    perform 1 from public.excursions where id=(payload->>'excursion_id')::bigint for update;
    if not found then raise exception 'Excursion not found' using errcode='P0002'; end if;
    if (payload->>'seat_number')::int not in (1,2) or payload->>'seat_number' is null then raise exception 'Seats 1 or 2 only' using errcode='22023'; end if;
    if action='permission' then
      result:=private.write_fields('seat_permissions',null,payload,array['excursion_id','user_id','excursion_date','seat_number']);
      return jsonb_build_object('message','Разрешение создано','permission',result);
    end if;
    if exists(select 1 from public.seat_access_requests where excursion_id=(payload->>'excursion_id')::bigint and user_id=uid
      and excursion_date=(payload->>'excursion_date')::date and seat_number=(payload->>'seat_number')::int and status='pending') then
      raise exception 'Request already pending' using errcode='22023'; end if;
    if length(payload->>'reason')>500 then raise exception 'Reason too long' using errcode='22023'; end if;
    result:=private.write_fields('seat_access_requests',null,payload || jsonb_build_object('user_id',uid),array['excursion_id','user_id','excursion_date','seat_number','reason']);
    return jsonb_build_object('message','Запрос создан','request',result);
  when 'delete-permission' then
    delete from public.seat_permissions where id=target_id;
    if not found then raise exception 'Permission not found' using errcode='P0002'; end if;
  when 'approve','reject' then
    select * into r from public.seat_access_requests where id=target_id for update;
    if not found then raise exception 'Request not found' using errcode='P0002'; end if;
    if r.status<>'pending' then raise exception 'Request already processed' using errcode='22023'; end if;
    update public.seat_access_requests set status=case action when 'approve' then 'approved' else 'rejected' end,
      reviewed_by=uid,reviewed_at=now() where id=target_id;
    if action='approve' then
      insert into public.seat_permissions(excursion_id,user_id,excursion_date,seat_number)
        values(r.excursion_id,r.user_id,r.excursion_date,r.seat_number) on conflict do nothing;
    end if;
  else raise exception 'Unknown action' using errcode='22023';
  end case;
  return jsonb_build_object('message',case action when 'approve' then 'Запрос одобрен, разрешение создано' when 'reject' then 'Запрос отклонен' else 'Разрешение удалено' end);
end $$;

-- All settlement operations serialize on booking rows before locking sheets.
-- Global transaction advisory lock also orders deployed update/cancel RPCs via
-- the booking trigger below, avoiding price/detachment/creation write skew.
create function private.lock_accounting() returns trigger
language plpgsql set search_path = '' as $$
begin
  perform pg_advisory_xact_lock(20261028,5);
  return null;
end $$;
create trigger serialize_booking_accounting before update or delete on public.bookings
for each statement execute function private.lock_accounting();

create function public.manage_settlement(action text, target_id bigint default null, payload jsonb default '{}')
returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid bigint:=private.current_profile_id(); seller bigint; s public.settlements; ids bigint[]; n integer; total numeric; deleted boolean;
begin
  if uid is null then raise exception 'Authentication required' using errcode='42501'; end if;
  perform pg_advisory_xact_lock(20261028,5);
  if action='create' then
    seller:=(payload->>'seller_id')::bigint;
    if seller is null then raise exception 'Seller required' using errcode='22023'; end if;
  else
    select * into s from public.settlements where id=target_id for update;
    if not found then raise exception 'Settlement not found' using errcode='P0002'; end if;
    seller:=s.seller_id;
  end if;
  if seller<>uid and not private.is_admin() then raise exception 'Own settlements only' using errcode='42501'; end if;
  if not exists(select 1 from public.profiles p join public.app_roles r on r.id=p.role_id where p.id=seller and r.name in ('Организатор экскурсии','Партнер','Продавец')) then
    raise exception 'Not a seller' using errcode='22023'; end if;
  case action
  when 'create' then
    if jsonb_typeof(payload->'booking_ids') is distinct from 'array' or jsonb_array_length(payload->'booking_ids')=0 then raise exception 'Bookings required' using errcode='22023'; end if;
    select array_agg(value::bigint) into ids from jsonb_array_elements_text(payload->'booking_ids');
    if cardinality(ids)<>(select count(distinct x) from unnest(ids) x) then raise exception 'Duplicate booking IDs' using errcode='22023'; end if;
    perform 1 from public.bookings where id=any(ids) order by id for update;
    select count(*),sum(price) into n,total from public.bookings where id=any(ids) and booked_by=seller
      and not exists(select 1 from public.settlement_booking where booking_id=bookings.id);
    if n<>cardinality(ids) then raise exception 'Missing, foreign or settled booking' using errcode='22023'; end if;
    insert into public.settlements(seller_id,total_amount,notes,settlement_date,date_from,date_to)
      values(seller,total,payload->>'notes',(now() at time zone 'Europe/Moscow')::date,(payload->>'date_from')::date,(payload->>'date_to')::date) returning * into s;
    insert into public.settlement_booking(settlement_id,booking_id) select s.id,x from unnest(ids) x;
    return jsonb_build_object('message','Расчет создан успешно','settlement',to_jsonb(s) || jsonb_build_object('bookings_count',n));
  when 'delete' then
    delete from public.settlement_booking where settlement_id=target_id;
    delete from public.settlements where id=target_id;
  when 'remove-booking' then
    delete from public.settlement_booking where settlement_id=target_id and booking_id=(payload->>'booking_id')::bigint;
    if not found then raise exception 'Booking not in settlement' using errcode='P0002'; end if;
    deleted:=not exists(select 1 from public.settlements where id=target_id);
    return jsonb_build_object('message',case when deleted then 'Расчет отменен (не осталось продаж)' else 'Продажа удалена из расчета' end,'settlement_deleted',deleted);
  else raise exception 'Unknown action' using errcode='22023';
  end case;
  -- Settlements mark sales as settled; Laravel does not debit the wallet here.
  return jsonb_build_object('message','Расчет отменен успешно');
end $$;

revoke all on function public.manage_bus(text,bigint,jsonb),public.manage_user(text,bigint,jsonb),public.manage_seat_access(text,bigint,jsonb),public.manage_settlement(text,bigint,jsonb) from public,anon;
grant execute on function public.manage_bus(text,bigint,jsonb),public.manage_user(text,bigint,jsonb),public.manage_seat_access(text,bigint,jsonb),public.manage_settlement(text,bigint,jsonb) to authenticated;
revoke all on all functions in schema private from public,anon,authenticated;
