-- Forward-only Laravel compatibility operations. No grants for direct writes.
-- SECURITY DEFINER entry points derive identity only from auth.uid(), never JSON.
-- Invariants: lock the excursion before changing seats, dates or assignments;
-- settlement membership is exclusive; totals equal current member ticket prices;
-- wallet deltas track money collected (price - debt), not uncollected debt.
alter table public.excursions
  add column price_concession_without_entry numeric(10,2),
  add column price_concession_with_entry numeric(10,2),
  add column price_concession_seller_commission numeric(5,2),
  add column price_concession_partner_commission numeric(5,2);

-- Existing duplicate settlement membership must be reconciled explicitly rather
-- than silently discarded by a migration.
create unique index settlement_booking_one_settlement on public.settlement_booking(booking_id);
revoke insert on public.seat_access_requests from authenticated;

create function private.require_admin() returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not private.is_admin() then
    raise exception 'Administrator required' using errcode = '42501';
  end if;
end $$;

-- Internal typed, allowlisted patcher. Only trusted functions choose the table
-- and allowed columns. Identifiers are quoted; values are bound parameters.
create function private.write_fields(t text, target bigint, body jsonb, allowed text[])
returns jsonb language plpgsql set search_path = '' as $$
declare cols text; vals text; result jsonb;
begin
  if jsonb_typeof(body) is distinct from 'object' or body = '{}'::jsonb
    or exists(select 1 from jsonb_object_keys(body) k where not k = any(allowed)) then
    raise exception 'Unsupported or empty fields' using errcode = '22023';
  end if;
  select string_agg(format('%I', k), ',' order by k),
    string_agg(format('r.%I', k), ',' order by k)
  into cols, vals from jsonb_object_keys(body) k;
  if target is null then
    execute format('insert into public.%1$I (%2$s) select %3$s from jsonb_populate_record(null::public.%1$I,$1) r returning to_jsonb(%1$I.*)',t,cols,vals)
      into result using body;
  else
    execute format('update public.%1$I set (%2$s) = (select %3$s from jsonb_populate_record(null::public.%1$I,$1) r) where id=$2 returning to_jsonb(%1$I.*)',t,cols,vals)
      into result using body,target;
    if result is null then raise exception 'Not found' using errcode = 'P0002'; end if;
  end if;
  return result;
end $$;

-- Maintain totals on cancellation, ticket-price edits and explicit detachment,
-- including calls to the already deployed booking RPCs. Empty sheets disappear.
create function private.refresh_settlement(sid bigint) returns void
language plpgsql security definer set search_path = '' as $$
declare total numeric; n bigint;
begin
  perform 1 from public.settlements where id=sid for update;
  select count(*), coalesce(sum(b.price),0) into n,total
  from public.settlement_booking sb join public.bookings b on b.id=sb.booking_id
  where sb.settlement_id=sid;
  if n=0 then delete from public.settlements where id=sid;
  else update public.settlements set total_amount=total where id=sid; end if;
end $$;

create function private.settlement_member_changed() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  perform private.refresh_settlement(old.settlement_id);
  return old;
end $$;
create trigger settlement_detached after delete on public.settlement_booking
for each row execute function private.settlement_member_changed();

create function private.booking_price_changed() returns trigger
language plpgsql security definer set search_path = '' as $$
declare sid bigint;
begin
  for sid in select settlement_id from public.settlement_booking where booking_id=new.id order by settlement_id loop
    perform private.refresh_settlement(sid);
  end loop;
  return new;
end $$;
create trigger settled_price_changed after update of price on public.bookings
for each row when (old.price is distinct from new.price)
execute function private.booking_price_changed();

-- Reusable allocation matches BusController: first contiguous free range,
-- capped by capacity and excursion max_seats; gaps and partial buses are valid.
create function private.allocate_bus(eid bigint, bid bigint, uid bigint, d date, tm text)
returns jsonb language plpgsql set search_path = '' as $$
declare e public.excursions; b public.buses; a public.excursion_bus_assignments;
  first_seat integer; last_seat integer; n integer;
begin
  select * into strict e from public.excursions where id=eid for update;
  select * into strict b from public.buses where id=bid for update;
  if d is null or tm is null or tm !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' then
    raise exception 'Date/time required' using errcode='22023';
  end if;
  if not exists(select 1 from public.profiles where id=uid and role_id=3 and bus_id=bid) then
    raise exception 'Driver must belong to bus' using errcode='22023';
  end if;
  select min(s) into first_seat from generate_series(1,e.max_seats) s
  where not exists(select 1 from public.excursion_bus_assignments x
    where x.excursion_id=eid and x.excursion_date=d and x.time=tm and s between x.seat_from and x.seat_to);
  if first_seat is null then raise exception 'No free range' using errcode='23514'; end if;
  last_seat := least(e.max_seats,first_seat+b.capacity-1);
  select min(seat_from)-1 into n from public.excursion_bus_assignments
    where excursion_id=eid and excursion_date=d and time=tm and seat_from>first_seat;
  last_seat := least(last_seat,coalesce(n,last_seat));
  insert into public.excursion_bus_assignments(excursion_id,excursion_date,time,bus_id,driver_id,seat_from,seat_to)
  values(eid,d,tm,bid,uid,first_seat,last_seat) returning * into a;
  insert into public.excursion_user(excursion_id,user_id,role_in_excursion,excursion_date,time)
  values(eid,uid,'driver',d,tm) on conflict do nothing;
  return to_jsonb(a) || jsonb_build_object('allocated_seats',last_seat-first_seat+1,
    'bus',jsonb_build_object('id',b.id,'number',b.number,'capacity',b.capacity),
    'driver',(select jsonb_build_object('id',id,'name',name) from public.profiles where id=uid));
end $$;

create function private.excursion_result(eid bigint) returns jsonb
language sql stable set search_path = '' as $$
  select to_jsonb(e) || jsonb_build_object(
    'prices',coalesce((select jsonb_agg(p order by p.id) from public.excursion_prices p where p.excursion_id=e.id),'[]'::jsonb),
    'staff_prices',coalesce((select jsonb_agg(p order by p.id) from public.staff_prices p where p.excursion_id=e.id),'[]'::jsonb),
    'bus_seats',coalesce((select jsonb_agg(s order by s.seat_number) from public.bus_seats s where s.excursion_id=e.id),'[]'::jsonb),
    'assigned_staff',coalesce((select jsonb_agg(to_jsonb(a) || jsonb_build_object('id',p.id,'name',p.name,'email',p.email) order by a.id)
      from public.excursion_user a join public.profiles p on p.id=a.user_id where a.excursion_id=e.id),'[]'::jsonb),
    'bus_assignments',coalesce((select jsonb_agg(to_jsonb(a) || jsonb_build_object('allocated_seats',a.seat_to-a.seat_from+1,
      'bus',jsonb_build_object('id',b.id,'number',b.number,'model',b.model,'capacity',b.capacity),
      'driver',jsonb_build_object('id',p.id,'name',p.name,'email',p.email)) order by a.id)
      from public.excursion_bus_assignments a join public.buses b on b.id=a.bus_id join public.profiles p on p.id=a.driver_id where a.excursion_id=e.id),'[]'::jsonb),
    'booked_seats_count',(select count(*) from public.bus_seats s where s.excursion_id=e.id and s.status in ('booked','reserved')),
    'available_seats_count',e.max_seats-(select count(*) from public.bus_seats s where s.excursion_id=e.id and s.status in ('booked','reserved')),
    'unscheduled_dates',coalesce((select jsonb_agg(u) from public.unscheduled_excursion_dates u where u.excursion_id=e.id and u.deleted_at is null),'[]'::jsonb),
    'deleted_unscheduled_dates',coalesce((select jsonb_agg(u) from public.unscheduled_excursion_dates u where u.excursion_id=e.id and u.deleted_at is not null),'[]'::jsonb),
    '__schedule_days',coalesce((select jsonb_agg(d order by d.weekday) from public.schedule_days d where d.schedule_template_id=e.schedule_template_id),'[]'::jsonb),
    '__cancelled_dates',coalesce((select jsonb_agg(d) from public.cancelled_excursion_dates d where d.excursion_id=e.id),'[]'::jsonb))
  from public.excursions e where id=eid
$$;

create function public.manage_excursion(action text, target_id bigint default null, child_id bigint default null, payload jsonb default '{}')
returns jsonb language plpgsql security definer set search_path = '' as $$
declare e public.excursions; item jsonb; result jsonb; v_type text; v_date date;
  tm text; dt timestamptz; lim integer; uid bigint; bid bigint; n integer:=0; booking_id bigint;
  tariff jsonb; cols text;
begin
  perform private.require_admin();
  if action='create' then
    if not payload ?& array['schedule_template_id','title','price','max_seats'] or payload->>'price' is null or payload->>'max_seats' is null then
      raise exception 'Required excursion fields missing' using errcode='22023'; end if;
    perform 1 from public.schedule_templates where id=(payload->>'schedule_template_id')::bigint for update;
    if not found then raise exception 'Template not found' using errcode='P0002'; end if;
    if exists(select 1 from public.excursions where schedule_template_id=(payload->>'schedule_template_id')::bigint) then
      raise exception 'Template already has excursion' using errcode='22023'; end if;
    result:=private.write_fields('excursions',null,payload,array['schedule_template_id','title','description','direction','price','max_seats','is_active']);
    target_id:=(result->>'id')::bigint;
    insert into public.excursion_prices(excursion_id,passenger_type,price,price_without_entry,price_with_entry)
      select target_id,t,(payload->>'price')::numeric,(payload->>'price')::numeric,(payload->>'price')::numeric
      from unnest(array['adult','child','senior','disabled','special']) t;
  else
    select * into e from public.excursions where id=target_id for update;
    if not found then raise exception 'Excursion not found' using errcode='P0002'; end if;
    case action
    when 'update' then
      if exists(select 1 from jsonb_each(payload) x where x.key in ('schedule_template_id','title','price','max_seats','direction','is_active') and x.value='null'::jsonb) then
        raise exception 'Required excursion field cannot be null' using errcode='22023'; end if;
      if payload ? 'max_seats' and exists(select 1 from public.bookings b join public.bus_seats s on s.id=b.bus_seat_id where b.excursion_id=target_id and s.seat_number>(payload->>'max_seats')::int) then
        raise exception 'Capacity below booked seat' using errcode='23514'; end if;
      if payload ? 'schedule_template_id' then
        perform 1 from public.schedule_templates where id=(payload->>'schedule_template_id')::bigint for update;
        if exists(select 1 from public.excursions where id<>target_id and schedule_template_id=(payload->>'schedule_template_id')::bigint) then
          raise exception 'Template already has excursion' using errcode='22023'; end if;
      end if;
      result:=private.write_fields('excursions',target_id,payload,array['schedule_template_id','title','description','direction','price','max_seats','is_active']);
      if exists(select 1 from public.excursion_bus_assignments where excursion_id=target_id and seat_to>(result->>'max_seats')::int)
        or exists(select 1 from public.excursion_slot_limits where excursion_id=target_id and max_seats>(result->>'max_seats')::int) then
        raise exception 'Capacity below assignment or slot limit' using errcode='23514'; end if;
      delete from public.bus_seats where excursion_id=target_id and seat_number>(result->>'max_seats')::int;
    when 'delete' then
      for booking_id in select id from public.bookings where excursion_id=target_id order by id loop
        perform public.cancel_booking(booking_id,'Удаление экскурсии');
      end loop;
      delete from public.excursions where id=target_id;
      return jsonb_build_object('message','Экскурсия удалена');
    when 'prices' then
      foreach v_type in array array['adult','child','senior','disabled','special','concession'] loop
        item:=payload->'prices'->v_type;
        if item is null or not item ?& array['price','seller_commission_percent','partner_commission_percent'] or item->>'price' is null then
          raise exception 'All six tariffs required' using errcode='22023'; end if;
        tariff:=item || jsonb_build_object('price_without_entry',coalesce(item->>'price_without_entry',item->>'price')::numeric,
          'price_with_entry',coalesce(item->>'price_with_entry',item->>'price')::numeric);
        select id into uid from public.excursion_prices where excursion_id=target_id and passenger_type=v_type;
        if uid is null then
          perform private.write_fields('excursion_prices',null,tariff || jsonb_build_object('excursion_id',target_id,'passenger_type',v_type),
            array['excursion_id','passenger_type','price','price_without_entry','price_with_entry','seller_commission_percent','partner_commission_percent']);
        else
          perform private.write_fields('excursion_prices',uid,tariff,array['price','price_without_entry','price_with_entry','seller_commission_percent','partner_commission_percent']);
        end if;
        -- Keep the denormalized columns used by legacy admin screens in sync.
        execute format('update public.excursions set %I=$1,%I=$2,%I=$3,%I=$4 where id=$5',
          'price_'||v_type||'_without_entry','price_'||v_type||'_with_entry',
          'price_'||v_type||'_seller_commission','price_'||v_type||'_partner_commission')
        using (tariff->>'price_without_entry')::numeric,(tariff->>'price_with_entry')::numeric,
          (tariff->>'seller_commission_percent')::numeric,(tariff->>'partner_commission_percent')::numeric,target_id;
      end loop;
    when 'staff-prices' then
      if jsonb_typeof(payload->'staff_prices') is distinct from 'array' then raise exception 'Array required' using errcode='22023'; end if;
      delete from public.staff_prices where excursion_id=target_id;
      for item in select value from jsonb_array_elements(payload->'staff_prices') loop
        perform private.write_fields('staff_prices',null,item || jsonb_build_object('excursion_id',target_id),
          array['excursion_id','staff_type','min_passengers','max_passengers','price']);
      end loop;
    when 'actual-amount' then
      perform private.write_fields('excursions',target_id,jsonb_build_object('actual_amount',payload->'actual_amount'),array['actual_amount']);
    when 'unscheduled-date' then
      dt:=(payload->>'date_time')::timestamp at time zone 'Europe/Moscow';
      if payload->>'date_time' ~ '(Z|[+-][0-9]{2}:[0-9]{2})$' then dt:=(payload->>'date_time')::timestamptz; end if;
      if dt is null then raise exception 'Date required' using errcode='22023'; end if;
      insert into public.unscheduled_excursion_dates(excursion_id,date_time) values(target_id,dt);
    when 'delete-unscheduled-date' then
      update public.unscheduled_excursion_dates set deleted_at=now() where id=child_id and excursion_id=target_id;
      if not found then raise exception 'Date not found' using errcode='P0002'; end if;
    when 'cancel-date' then
      dt:=(payload->>'date_time')::timestamp at time zone 'Europe/Moscow';
      if payload->>'date_time' ~ '(Z|[+-][0-9]{2}:[0-9]{2})$' then dt:=(payload->>'date_time')::timestamptz; end if;
      insert into public.cancelled_excursion_dates(excursion_id,date_time) values(target_id,dt) returning to_jsonb(cancelled_excursion_dates.*) into result;
      v_date:=(dt at time zone 'Europe/Moscow')::date; tm:=to_char(dt at time zone 'Europe/Moscow','HH24:MI');
      for booking_id in select id from public.bookings where excursion_id=target_id and time::time=tm::time
        and (excursion_date=v_date or (excursion_date is null and weekday=extract(isodow from v_date))) order by id loop
        perform public.cancel_booking(booking_id,'Возврат за отмененную экскурсию'); n:=n+1;
      end loop;
      return jsonb_build_object('message','Экскурсия отменена','cancelled_bookings_count',n,'data',result);
    when 'restore-date' then
      delete from public.cancelled_excursion_dates where id=child_id and excursion_id=target_id;
      if not found then raise exception 'Date not found' using errcode='P0002'; end if;
      return jsonb_build_object('message','Экскурсия восстановлена');
    when 'assign' then
      v_date:=(payload->>'excursion_date')::date; tm:=payload->>'time'; lim:=(payload->>'slot_max_seats')::int;
      if tm is not null and tm !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' then raise exception 'Invalid time' using errcode='22023'; end if;
      if jsonb_typeof(payload->'assignments') is distinct from 'array' then raise exception 'Assignments required' using errcode='22023'; end if;
      if lim is not null and (lim<1 or lim>e.max_seats or exists(select 1 from public.bookings b join public.bus_seats s on s.id=b.bus_seat_id
        where b.excursion_id=target_id and b.excursion_date=v_date and b.time=tm::time and s.seat_number>lim)) then
        raise exception 'Invalid slot limit' using errcode='23514'; end if;
      if v_date is not null and tm is not null and payload ? 'slot_max_seats' then
        delete from public.excursion_slot_limits where excursion_id=target_id and excursion_date=v_date and time=tm::time;
        if lim is not null then insert into public.excursion_slot_limits(excursion_id,excursion_date,time,max_seats) values(target_id,v_date,tm::time,lim); end if;
      end if;
      delete from public.excursion_user where excursion_id=target_id and excursion_date is not distinct from v_date and (tm is null or time=tm);
      delete from public.excursion_bus_assignments where excursion_id=target_id and excursion_date=v_date and time=tm;
      for item in select value from jsonb_array_elements(payload->'assignments') loop
        perform private.write_fields('excursion_user',null,item || jsonb_build_object('excursion_id',target_id,'excursion_date',v_date,'time',tm),
          array['excursion_id','user_id','role_in_excursion','excursion_date','time','manual_amount']);
        if item->>'role_in_excursion'='driver' and v_date is not null and tm is not null then
          uid:=(item->>'user_id')::bigint;
          select bus_id into bid from public.profiles where id=uid and role_id=3;
          if bid is not null and exists(select 1 from generate_series(1,e.max_seats) s where not exists(
            select 1 from public.excursion_bus_assignments a where a.excursion_id=target_id and a.excursion_date=v_date and a.time=tm and s between a.seat_from and a.seat_to)) then
            perform private.allocate_bus(target_id,bid,uid,v_date,tm);
          end if;
        end if;
      end loop;
      return jsonb_build_object('message','Назначения обновлены','assigned_users',payload->'assignments','excursion_date',v_date,'time',tm);
    when 'unassign' then
      delete from public.excursion_user where excursion_id=target_id and user_id=child_id;
      delete from public.excursion_bus_assignments where excursion_id=target_id and driver_id=child_id;
      return jsonb_build_object('message','Назначение отменено');
    else raise exception 'Unknown action' using errcode='22023';
    end case;
  end if;
  select * into e from public.excursions where id=target_id;
  if e.max_seats>100 or e.price<0 or e.actual_amount<0 or trim(e.title)='' or length(e.title)>255 then
    raise exception 'Invalid excursion fields' using errcode='23514'; end if;
  insert into public.bus_seats(excursion_id,seat_number) select target_id,s from generate_series(1,e.max_seats) s on conflict do nothing;
  return jsonb_build_object('message',case action when 'create' then 'Экскурсия создана' when 'prices' then 'Тарифы обновлены'
    when 'staff-prices' then 'Цены персонала обновлены' when 'actual-amount' then 'Фактическая сумма обновлена'
    when 'unscheduled-date' then 'Внеплановая дата добавлена' when 'delete-unscheduled-date' then 'Внеплановая дата удалена'
    else 'Экскурсия обновлена' end,'data',private.excursion_result(target_id));
end $$;

alter table public.excursion_prices add constraint tariff_nonnegative check
  (price>=0 and price_without_entry>=0 and price_with_entry>=0 and seller_commission_percent between 0 and 100 and partner_commission_percent between 0 and 100) not valid;
alter table public.staff_prices add constraint staff_price_nonnegative check(price>=0) not valid;
alter table public.excursion_user add constraint manual_amount_nonnegative check(manual_amount>=0) not valid;

revoke all on function public.manage_excursion(text,bigint,bigint,jsonb) from public,anon;
grant execute on function public.manage_excursion(text,bigint,bigint,jsonb) to authenticated;
revoke all on all functions in schema private from public,anon,authenticated;
