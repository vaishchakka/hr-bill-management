-- Admin-only session creation. Realtime publication is added separately.
begin;
create or replace function public.start_house_session()
returns jsonb
language plpgsql volatile security definer
set search_path = ''
as $$
declare
  active_session public.house_sessions%rowtype;
begin
  perform house_private.require_admin();

  -- Workspace lifecycle lock: future end/present functions must take this same
  -- lock before session/ballot row locks. Held until the transaction completes.
  -- This also serializes starts when there is no session row yet to lock.
  perform pg_catalog.pg_advisory_xact_lock(712804, 1);

  select s.* into active_session
    from public.house_sessions s where s.status = 'active';

  if active_session.id is null then
    insert into public.house_sessions (status, current_bill_id)
    values ('active', null)
    returning * into active_session;
  end if;

  -- Repeated starts return the same session without clearing its presentation,
  -- opening voting, or making a redundant database update.
  return jsonb_build_object(
    'id', active_session.id,
    'status', active_session.status,
    'current_bill_id', active_session.current_bill_id,
    'created_at', active_session.created_at
  );
end;
$$;
revoke execute on function public.start_house_session() from public, anon, authenticated;
grant execute on function public.start_house_session() to authenticated;
commit;
