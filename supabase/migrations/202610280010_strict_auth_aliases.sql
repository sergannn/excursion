-- Follow Supabase Auth's ASCII email validation for legacy login aliases.
update public.profiles set auth_login_email='legacy-' || id || '@login.invalid'
where auth_user_id is null
  and email !~ '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$';

create or replace function private.set_auth_login_email()
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
