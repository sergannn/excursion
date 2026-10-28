-- Durable compensation journal. No credentials or tokens are stored here.
create table private.identity_operations (
  id uuid primary key default gen_random_uuid(),
  actor_id bigint not null,
  target_id bigint not null unique,
  action text not null check (action in ('create','update','delete')),
  before_profile jsonb,
  created_at timestamptz not null default now()
);
revoke all on private.identity_operations from public, anon, authenticated;

create function private.profile_ready(profile_id bigint)
returns boolean language sql stable security definer set search_path = '' as $$
  select not exists(select 1 from private.identity_operations where target_id=profile_id)
$$;
revoke all on function private.profile_ready(bigint) from public,anon;
grant execute on function private.profile_ready(bigint) to authenticated;
drop policy authenticated_read_profiles on public.profiles;
create policy authenticated_read_profiles on public.profiles as restrictive for select to authenticated
  using (private.profile_ready(id));

-- A pending identity must not perform domain work while Auth/profile disagree.
create or replace function private.current_profile_id()
returns bigint language sql stable security definer set search_path = '' as $$
  select p.id from public.profiles p where p.auth_user_id=(select auth.uid())
    and not exists(select 1 from private.identity_operations o where o.target_id=p.id)
$$;
create or replace function private.current_role_id()
returns bigint language sql stable security definer set search_path = '' as $$
  select p.role_id from public.profiles p where p.id=private.current_profile_id()
$$;

alter function public.manage_user(text,bigint,jsonb) set schema private;
revoke all on function private.manage_user(text,bigint,jsonb) from public,anon,authenticated;
create function public.manage_user(action text, target_id bigint default null, payload jsonb default '{}')
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  perform private.require_admin();
  if action <> 'color' then raise exception 'Use identity coordinator' using errcode='42501'; end if;
  if exists(select 1 from private.identity_operations o where o.target_id=manage_user.target_id) then
    raise exception 'Identity operation pending' using errcode='23505'; end if;
  return private.manage_user(action,target_id,payload);
end $$;
revoke all on function public.manage_user(text,bigint,jsonb) from public,anon;
grant execute on function public.manage_user(text,bigint,jsonb) to authenticated;

create function public.begin_identity_operation(action text, target_id bigint default null, payload jsonb default '{}', operation_key uuid default gen_random_uuid())
returns jsonb language plpgsql security definer set search_path = '' as $$
declare actor bigint; old public.profiles; result jsonb; op uuid;
begin
  perform private.require_admin();
  actor:=private.current_profile_id();
  if action not in ('create','update','delete') then raise exception 'Invalid action' using errcode='22023'; end if;
  if payload ? 'auth_user_id' or payload ? 'password' then raise exception 'Invalid fields' using errcode='22023'; end if;
  if action='create' then
    result:=private.manage_user('create',null,payload);
    target_id:=(result->'user'->>'id')::bigint;
  else
    select * into old from public.profiles p where p.id=target_id for update;
    if not found then raise exception 'User not found' using errcode='P0002'; end if;
    -- Self mutation would lose the ability to finalize/compensate a role change.
    if target_id=actor then raise exception 'Cannot mutate current identity' using errcode='22023'; end if;
    if exists(select 1 from private.identity_operations o where o.target_id=begin_identity_operation.target_id) then
      raise exception 'Identity operation pending' using errcode='23505'; end if;
    if action='delete' then
      if old.role_id=1 then raise exception 'Cannot delete administrator' using errcode='42501'; end if;
      -- Check actual FK restrictions before the irreversible Auth deletion.
      -- The subtransaction rolls back the probe, including cascades.
      begin
        perform private.manage_user('delete',target_id,'{}');
        raise exception 'probe rollback' using errcode='Z0001';
      exception when sqlstate 'Z0001' then null; end;
      result:=jsonb_build_object('message','Пользователь удалён');
    elsif payload='{}'::jsonb then
      result:=jsonb_build_object('message','Пользователь сохранен','user',
        (to_jsonb(old)-'auth_user_id') || jsonb_build_object('role',(select name from public.app_roles where id=old.role_id)));
    else result:=private.manage_user('update',target_id,payload);
    end if;
  end if;
  insert into private.identity_operations(id,actor_id,target_id,action,before_profile)
    values(operation_key,actor,target_id,action,case when old.id is null then null else to_jsonb(old) end) returning id into op;
  return jsonb_build_object('operation_id',op,'target_id',target_id,'auth_user_id',old.auth_user_id,'result',result);
end $$;

create function public.finish_identity_operation(operation_id uuid, commit_change boolean)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare o private.identity_operations; old public.profiles;
begin
  perform private.require_admin();
  select * into o from private.identity_operations where id=operation_id for update;
  if not found or o.actor_id<>private.current_profile_id() then raise exception 'Operation unavailable' using errcode='42501'; end if;
  if commit_change and o.action='delete' then
    if exists(select 1 from auth.users where id=(o.before_profile->>'auth_user_id')::uuid) then
      raise exception 'Auth identity still exists' using errcode='23514'; end if;
    perform private.manage_user('delete',o.target_id,'{}');
  elsif commit_change then
    if not exists(select 1 from public.profiles p join auth.users a on a.id=p.auth_user_id
      where p.id=o.target_id and lower(a.email)=lower(p.email)) then
      raise exception 'Auth/profile mismatch' using errcode='23514'; end if;
  elsif not commit_change then
    if o.action='create' then
      if exists(select 1 from public.profiles where id=o.target_id and auth_user_id is not null) then
        raise exception 'Remove newly created Auth account before rollback' using errcode='23514'; end if;
      delete from public.profiles where id=o.target_id;
    else
      old:=jsonb_populate_record(null::public.profiles,o.before_profile);
      update public.profiles set name=old.name,email=old.email,role_id=old.role_id,
        color=old.color,bus_id=old.bus_id where id=o.target_id;
    end if;
  end if;
  delete from private.identity_operations where id=o.id;
  return jsonb_build_object('message','Identity operation completed');
end $$;
revoke all on function public.begin_identity_operation(text,bigint,jsonb,uuid),public.finish_identity_operation(uuid,boolean) from public,anon;
grant execute on function public.begin_identity_operation(text,bigint,jsonb,uuid),public.finish_identity_operation(uuid,boolean) to authenticated;

-- Ordinary signup must never claim a pre-existing profile by knowing its email.
-- Only the unpredictable operation nonce sent through the Auth admin API may
-- link a reserved profile; existing numeric IDs are retained.
create or replace function private.handle_new_auth_user()
returns trigger language plpgsql security definer set search_path = '' as $$
declare target bigint;
begin
  select p.id into target from public.profiles p join private.identity_operations o on o.target_id=p.id
    where p.email=new.email and p.auth_user_id is null
      and o.id::text=new.raw_user_meta_data->>'identity_operation';
  if target is not null then
    update public.profiles set auth_user_id=new.id where id=target;
  else
    insert into public.profiles(auth_user_id,role_id,email,name)
      values(new.id,2,new.email,coalesce(new.raw_user_meta_data->>'name',split_part(new.email,'@',1)));
  end if;
  return new;
end $$;
