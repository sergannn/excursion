-- Supabase Auth requires email-shaped identifiers, while the legacy Laravel
-- installation contains two short login values. Keep the original profile
-- value and map it to an internal, non-deliverable Auth alias.
alter table public.profiles add column auth_login_email text;

update public.profiles p set auth_login_email=coalesce(
  (select lower(a.email) from auth.users a where a.id=p.auth_user_id),
  case when p.email ~ '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$'
    then lower(p.email)
    else 'legacy-' || p.id || '@login.invalid'
  end
);

alter table public.profiles alter column auth_login_email set not null;
alter table public.profiles add constraint profiles_auth_login_email_unique unique(auth_login_email);

create function private.set_auth_login_email()
returns trigger language plpgsql set search_path = '' as $$
begin
  if new.auth_login_email is null then
    new.auth_login_email:=case
      when new.email ~ '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$' then lower(new.email)
      else 'legacy-' || new.id || '@login.invalid'
    end;
  elsif tg_op='UPDATE' and new.email is distinct from old.email then
    if new.email !~ '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$' then
      raise exception 'Invalid new login email' using errcode='22023';
    end if;
    new.auth_login_email:=lower(new.email);
  end if;
  return new;
end $$;
create trigger profiles_auth_login_email before insert or update of email on public.profiles
for each row execute function private.set_auth_login_email();

create or replace function private.handle_new_auth_user()
returns trigger language plpgsql security definer set search_path = '' as $$
declare target bigint;
begin
  select p.id into target
  from public.profiles p
  join private.identity_operations o on o.target_id=p.id
  where p.auth_user_id is null
    and o.id::text=new.raw_user_meta_data->>'identity_operation';
  if target is not null then
    update public.profiles set auth_user_id=new.id,auth_login_email=lower(new.email) where id=target;
  else
    insert into public.profiles(auth_user_id,role_id,email,auth_login_email,name)
    values(new.id,2,new.email,lower(new.email),coalesce(new.raw_user_meta_data->>'name',split_part(new.email,'@',1)));
  end if;
  return new;
end $$;

create function public.resolve_auth_login_email(login_value text)
returns text language sql stable security definer set search_path = '' as $$
  select coalesce((
    select p.auth_login_email from public.profiles p
    where (lower(p.email)=lower(login_value) or lower(p.auth_login_email)=lower(login_value))
      and p.auth_user_id is not null and private.profile_ready(p.id)
    limit 1
  ),login_value)
$$;
revoke all on function public.resolve_auth_login_email(text) from public;
grant execute on function public.resolve_auth_login_email(text) to anon,authenticated;

create function public.identity_auth_email(operation_id uuid)
returns text language sql stable security definer set search_path = '' as $$
  select p.auth_login_email
  from private.identity_operations o
  join public.profiles p on p.id=o.target_id
  where o.id=operation_id and o.actor_id=private.current_profile_id()
$$;
revoke all on function public.identity_auth_email(uuid) from public,anon;
grant execute on function public.identity_auth_email(uuid) to authenticated;

create or replace function public.finish_identity_operation(operation_id uuid, commit_change boolean)
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
      where p.id=o.target_id and lower(a.email)=lower(p.auth_login_email)) then
      raise exception 'Auth/profile mismatch' using errcode='23514'; end if;
  elsif not commit_change then
    if o.action='create' then
      if exists(select 1 from public.profiles where id=o.target_id and auth_user_id is not null) then
        raise exception 'Remove newly created Auth account before rollback' using errcode='23514'; end if;
      delete from public.profiles where id=o.target_id;
    else
      old:=jsonb_populate_record(null::public.profiles,o.before_profile);
      update public.profiles set name=old.name,email=old.email,role_id=old.role_id,
        color=old.color,bus_id=old.bus_id,auth_login_email=old.auth_login_email where id=o.target_id;
    end if;
  end if;
  delete from private.identity_operations where id=o.id;
  return jsonb_build_object('message','Identity operation completed');
end $$;
