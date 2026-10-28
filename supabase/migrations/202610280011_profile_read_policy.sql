-- A restrictive policy cannot grant SELECT by itself. Grant linked callers read
-- access to ready profiles while still hiding profiles during identity changes.
drop policy authenticated_read_profiles on public.profiles;
create policy authenticated_read_profiles on public.profiles for select to authenticated
using (private.current_profile_id() is not null and private.profile_ready(id));
