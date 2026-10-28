\set ON_ERROR_STOP on
begin;
create function pg_temp.assert(ok boolean, label text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception 'ASSERT: %',label; end if; end $$;
create function pg_temp.expect_error(stmt text, expected text) returns void language plpgsql as $$
begin
  begin execute stmt;
  exception when others then
    if sqlstate=expected then return; end if;
    raise exception 'Expected %, got %: %',expected,sqlstate,sqlerrm;
  end;
  raise exception 'Expected error % for %',expected,stmt;
end $$;
insert into auth.users(id,email) values
 ('00000000-0000-4000-8000-000000000001','admin@test.local'),
 ('00000000-0000-4000-8000-000000000002','seller@test.local'),
 ('00000000-0000-4000-8000-000000000003','driver@test.local');
update public.profiles set role_id=1 where email='admin@test.local';
update public.profiles set role_id=3 where email='driver@test.local';
select id as admin_id from public.profiles where email='admin@test.local' \gset
select id as seller_id from public.profiles where email='seller@test.local' \gset
select id as driver_id from public.profiles where email='driver@test.local' \gset
insert into public.schedule_templates(title) values('Test') returning id as template_id \gset
insert into public.stops(name) values('Stop') returning id as stop_id \gset
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',true);
select public.manage_excursion('create',null,null,jsonb_build_object('schedule_template_id',:template_id,'title','Test excursion','price',100,'max_seats',10)) as created \gset
select (:'created'::jsonb->'data'->>'id')::bigint as excursion_id \gset
select pg_temp.assert((select count(*)=10 from public.bus_seats where excursion_id=:excursion_id),'seats created');
select pg_temp.assert((select count(*)=5 from public.excursion_prices where excursion_id=:excursion_id),'default prices created');
select pg_temp.expect_error(format('select public.manage_excursion(''create'',null,null,''{"schedule_template_id":%s,"title":"Duplicate","price":1,"max_seats":2}'')',:template_id),'22023');
select public.manage_excursion('update',:excursion_id,null,'{"description":"Updated","max_seats":12}');
select pg_temp.assert((select count(*)=12 from public.bus_seats where excursion_id=:excursion_id),'capacity expansion creates seats');
select public.manage_excursion('actual-amount',:excursion_id,null,'{"actual_amount":55.50}');
select pg_temp.assert((select actual_amount=55.50 from public.excursions where id=:excursion_id),'actual amount');
select public.manage_excursion('staff-prices',:excursion_id,null,'{"staff_prices":[{"staff_type":"driver","min_passengers":0,"max_passengers":4,"price":30},{"staff_type":"guide","min_passengers":0,"max_passengers":null,"price":10}]}');
select pg_temp.expect_error(format('select public.manage_excursion(''staff-prices'',%s,null,''{"staff_prices":[{"staff_type":"guide","min_passengers":5,"max_passengers":2,"price":10}]}'')',:excursion_id),'23514');
select pg_temp.assert((select count(*)=2 from public.staff_prices where excursion_id=:excursion_id),'invalid replacement rolls back old tiers');
select public.manage_excursion('prices',:excursion_id,null,jsonb_build_object('prices',(
 select jsonb_object_agg(t,jsonb_build_object('price',100,'price_without_entry',null,'price_with_entry',120,'seller_commission_percent',12.5,'partner_commission_percent',20))
 from unnest(array['adult','child','senior','disabled','special','concession']) t)));
select pg_temp.assert((select price_concession_without_entry=100 and price_concession_with_entry=120 from public.excursions where id=:excursion_id),'concession mirrored columns');
select public.begin_identity_operation('create',null,'{"name":"New Seller","email":"new@test.local","role_id":2}') as new_user_result \gset
select (:'new_user_result'::jsonb->>'target_id')::bigint as new_user_id, :'new_user_result'::jsonb->>'operation_id' as identity_op \gset
select pg_temp.assert((select count(*)=0 from public.profiles where id=:new_user_id),'pending profile is hidden');
select pg_temp.expect_error(format('select public.finish_identity_operation(%L,true)',:'identity_op'),'23514');
reset role;
-- The Auth admin API inserts auth.users; the local bootstrap emulates its DB trigger.
select pg_temp.expect_error('insert into auth.users(id,email) values(''00000000-0000-4000-8000-000000000009'',''new@test.local'')','23505');
insert into auth.users(id,email,raw_user_meta_data) values('00000000-0000-4000-8000-000000000008','new@test.local',jsonb_build_object('identity_operation',:'identity_op'));
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000008',true);
select pg_temp.expect_error(format('select public.financial_context(%s)',:new_user_id),'42501');
select pg_temp.assert((select count(*)=0 from public.profiles where id=:new_user_id),'pending caller profile lookup denied');
select pg_temp.expect_error(format('select public.finish_identity_operation(%L,true)',:'identity_op'),'42501');
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',true);
select public.finish_identity_operation(:'identity_op',true);
select pg_temp.assert((select auth_user_id='00000000-0000-4000-8000-000000000008' from public.profiles where id=:new_user_id),'Auth linked original numeric ID');
select public.begin_identity_operation('update',:new_user_id,'{}') as password_only \gset
select public.finish_identity_operation((:'password_only'::jsonb->>'operation_id')::uuid,true);
select public.begin_identity_operation('update',:new_user_id,'{"name":"Changed"}') as identity_update \gset
select public.finish_identity_operation((:'identity_update'::jsonb->>'operation_id')::uuid,true);
select public.manage_user('color',:new_user_id,'{"color":"#123456"}');
select pg_temp.assert((select name='Changed' and color='#123456' from public.profiles where id=:new_user_id),'user update/color');
select public.begin_identity_operation('update',:new_user_id,'{"name":"Rollback"}') as identity_rollback \gset
select pg_temp.expect_error(format('select public.begin_identity_operation(''update'',%s,''{}'')',:new_user_id),'23505');
select pg_temp.expect_error(format('select public.manage_user(''color'',%s,''{"color":"#ffffff"}'')',:new_user_id),'23505');
select public.finish_identity_operation((:'identity_rollback'::jsonb->>'operation_id')::uuid,false);
select pg_temp.assert((select name='Changed' from public.profiles where id=:new_user_id),'compensation restores profile');
select public.begin_identity_operation('delete',:new_user_id) as identity_delete \gset
select pg_temp.expect_error(format('select public.finish_identity_operation(%L,true)',:'identity_delete'::jsonb->>'operation_id'),'23514');
reset role;
delete from auth.users where id='00000000-0000-4000-8000-000000000008';
set local role authenticated;
select public.finish_identity_operation((:'identity_delete'::jsonb->>'operation_id')::uuid,true);
select pg_temp.assert((select count(*)=0 from public.profiles where id=:new_user_id),'profile removed after Auth');
select pg_temp.expect_error(format('select public.begin_identity_operation(''delete'',%s)',:admin_id),'22023');
select pg_temp.expect_error('select public.manage_user(''create'',null,''{}'')','42501');
select pg_temp.expect_error('select * from private.identity_operations','42501');
select public.manage_bus('create',null,'{"number":"TEST","capacity":6}') as bus_result \gset
select (:'bus_result'::jsonb->'bus'->>'id')::bigint as bus_id \gset
select public.manage_bus('assign-driver',:bus_id,jsonb_build_object('driver_id',:driver_id));
select public.manage_excursion('assign',:excursion_id,null,jsonb_build_object('excursion_date','2026-11-01','time','12:00','slot_max_seats',8,
 'assignments',jsonb_build_array(jsonb_build_object('user_id',:driver_id,'role_in_excursion','driver','manual_amount',77))));
select pg_temp.assert((select seat_from=1 and seat_to=6 from public.excursion_bus_assignments where excursion_id=:excursion_id),'automatic bus allocation');
select public.manage_seat_access('permission',null,jsonb_build_object('excursion_id',:excursion_id,'user_id',:seller_id,'excursion_date','2026-11-01','seat_number',1));
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000002',true);
select pg_temp.expect_error('select public.manage_user(''create'',null,''{"name":"Forged","email":"forged@test.local","role_id":1}'')','42501');
select pg_temp.expect_error('select public.begin_identity_operation(''create'',null,''{"name":"Forged","email":"forged@test.local","role_id":1}'')','42501');
select pg_temp.expect_error(format('select public.manage_excursion(''delete'',%s)',:excursion_id),'42501');
select pg_temp.expect_error(format('select public.financial_context(%s)',:admin_id),'42501');
select pg_temp.expect_error('insert into public.seat_access_requests(excursion_id,user_id,excursion_date,seat_number) values(1,1,current_date,1)','42501');
select public.manage_seat_access('request',null,jsonb_build_object('excursion_id',:excursion_id,'excursion_date','2026-11-01','seat_number',2,'reason','Please')) as access_result \gset
select (:'access_result'::jsonb->'request'->>'id')::bigint as request_id \gset
select pg_temp.expect_error(format('select public.manage_seat_access(''request'',null,''{"excursion_id":%s,"excursion_date":"2026-11-01","seat_number":2}'')',:excursion_id),'22023');
select pg_temp.expect_error(format('select public.manage_seat_access(''approve'',%s)',:request_id),'42501');
select public.create_bookings(:excursion_id,'2026-11-01','12:00',7::smallint,:stop_id,
 '[{"seat_number":1,"passenger_type":"adult","price":100,"debt":20,"customer_name":"A","customer_phone":"1"},{"seat_number":3,"passenger_type":"child","price":100,"customer_name":"B","customer_phone":"2"}]',null) as booking_result \gset
select (:'booking_result'::jsonb->'bookings'->0->>'id')::bigint as booking_1,
 (:'booking_result'::jsonb->'bookings'->1->>'id')::bigint as booking_2 \gset
select pg_temp.assert((select sum(amount)=180 from public.wallet_transactions where user_id=:seller_id),'collected money ledger');
select public.manage_settlement('create',null,jsonb_build_object('seller_id',:seller_id,'booking_ids',jsonb_build_array(:booking_1,:booking_2))) as sheet_result \gset
select (:'sheet_result'::jsonb->'settlement'->>'id')::bigint as sheet_id \gset
select pg_temp.assert((select total_amount=200 from public.settlements where id=:sheet_id),'settlement uses gross ticket prices');
select pg_temp.expect_error(format('select public.manage_settlement(''create'',null,''{"seller_id":%s,"booking_ids":[%s]}'')',:seller_id,:booking_1),'22023');
select pg_temp.expect_error(format('select public.manage_settlement(''create'',null,''{"seller_id":%s,"booking_ids":[%s,%s]}'')',:seller_id,:booking_2,:booking_2),'22023');
select public.update_booking(:booking_1,'{"price":120}');
select pg_temp.assert((select total_amount=220 from public.settlements where id=:sheet_id),'price edit updates sheet');
select public.manage_settlement('remove-booking',:sheet_id,jsonb_build_object('booking_id',:booking_2));
select pg_temp.assert((select total_amount=120 from public.settlements where id=:sheet_id),'remove recalculates sheet');
select public.cancel_booking(:booking_1,'test');
select pg_temp.assert(not exists(select 1 from public.settlements where id=:sheet_id),'empty sheet removed on cancellation');
select pg_temp.assert((select sum(amount)=100 from public.wallet_transactions where user_id=:seller_id),'refund excludes unpaid debt');
select pg_temp.assert((public.financial_context(:seller_id)->'bookings'->0->>'id')::bigint=:booking_2,'own report data');
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',true);
select public.manage_seat_access('approve',:request_id);
select pg_temp.expect_error(format('select public.manage_seat_access(''reject'',%s)',:request_id),'22023');
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000003',true);
select pg_temp.assert((public.financial_context(:driver_id)->'staff_slots'->0->>'passenger_count')::int=1,'staff aggregate counts other seller');
select pg_temp.assert(jsonb_array_length(public.financial_context(:driver_id)->'bookings')=0,'staff context contains no other seller PII');
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000099',true);
select pg_temp.expect_error(format('select public.update_booking(%s,''{"price":1}'')',:booking_2),'42501');
select pg_temp.expect_error(format('select public.cancel_booking(%s,''forged'')',:booking_2),'42501');
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',true);
select public.manage_excursion('cancel-date',:excursion_id,null,'{"date_time":"2026-11-01T12:00:00+03:00"}') as cancellation \gset
select pg_temp.assert((:'cancellation'::jsonb->>'cancelled_bookings_count')::int=1,'date cancellation removed remaining booking');
select pg_temp.assert((select sum(amount)=0 from public.wallet_transactions where user_id=:seller_id),'all refunds balanced');
select pg_temp.assert(not exists(select 1 from public.bookings where excursion_id=:excursion_id),'date cancellation atomic');
select public.manage_excursion('restore-date',:excursion_id,(:'cancellation'::jsonb->'data'->>'id')::bigint);
select public.manage_excursion('unscheduled-date',:excursion_id,null,'{"date_time":"2026-11-02 11:00"}');
select id as extra_id from public.unscheduled_excursion_dates where excursion_id=:excursion_id \gset
select public.manage_excursion('delete-unscheduled-date',:excursion_id,:extra_id);
select pg_temp.assert((select deleted_at is not null from public.unscheduled_excursion_dates where id=:extra_id),'extra date soft delete');
select public.manage_bus('unassign-excursion',:bus_id,jsonb_build_object('excursion_id',:excursion_id,'excursion_date','2026-11-01','time','12:00'));
select pg_temp.assert(not exists(select 1 from public.excursion_user where excursion_id=:excursion_id and user_id=:driver_id),'bus unassignment removes driver pivot');
select public.manage_excursion('delete',:excursion_id);
select pg_temp.assert(not exists(select 1 from public.excursions where id=:excursion_id),'excursion deletion');
rollback;
