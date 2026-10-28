-- Preserve deployed booking implementations behind authenticated wrappers.
-- Acquire the accounting lock BEFORE their SELECT FOR UPDATE, so settlement
-- creation, ticket-price edits and refunds share one lock order. Unlinked JWTs
-- must never pass SQL's NULL ownership comparison in the original functions.
alter function public.update_booking(bigint,jsonb) set schema private;
alter function public.cancel_booking(bigint,text) set schema private;
create function public.update_booking(p_booking_id bigint,p_changes jsonb)
returns public.bookings language plpgsql security definer set search_path = '' as $$
begin
  if private.current_profile_id() is null then raise exception 'Authentication required' using errcode='42501'; end if;
  perform pg_advisory_xact_lock(20261028,5);
  return private.update_booking(p_booking_id,p_changes);
end $$;
create function public.cancel_booking(p_booking_id bigint,p_reason text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  if private.current_profile_id() is null then raise exception 'Authentication required' using errcode='42501'; end if;
  perform pg_advisory_xact_lock(20261028,5);
  return private.cancel_booking(p_booking_id,p_reason);
end $$;
revoke all on function public.update_booking(bigint,jsonb),public.cancel_booking(bigint,text) from public,anon;
grant execute on function public.update_booking(bigint,jsonb),public.cancel_booking(bigint,text) to authenticated;
revoke all on all functions in schema private from public,anon,authenticated;
-- Policies store references to these four identity predicates. They disclose no
-- rows and must remain executable even though private schema is not exposed.
grant execute on function private.current_profile_id(),private.current_role_id(),private.is_admin(),private.is_assigned_staff(bigint,date,time) to anon,authenticated;
