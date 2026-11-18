-- End only the specified session; never implicitly target a newer session.
begin;
create or replace function public.end_house_session(p_session_id uuid)
returns jsonb
language plpgsql volatile security definer
set search_path = ''
as $$
declare
  target_session public.house_sessions%rowtype;
begin
  perform house_private.require_admin();
  if p_session_id is null then
    raise exception 'Session ID is required' using errcode = '22023';
  end if;

  -- Same lifecycle lock as start; always take it before session/ballot locks.
  perform pg_catalog.pg_advisory_xact_lock(712804, 1);
  select s.* into target_session from public.house_sessions s
    where s.id = p_session_id for update;
  if not found then
    raise exception 'Session not found' using errcode = 'P0002';
  end if;

  -- Lock ballots in deterministic order. Future vote commands must lock the
  -- session first, then ballot, and recheck session/ballot state after locking.
  perform b.id from public.house_ballots b
    where b.session_id = p_session_id order by b.id for update;
  update public.house_ballots set status = 'closed'
    where session_id = p_session_id and status = 'open';

  if target_session.status <> 'ended' or target_session.current_bill_id is not null then
    update public.house_sessions set status = 'ended', current_bill_id = null
      where id = p_session_id returning * into target_session;
  end if;

  -- Bills, votes, closed ballots, and finalized results are retained.
  return jsonb_build_object(
    'id', target_session.id,
    'status', target_session.status,
    'current_bill_id', target_session.current_bill_id,
    'created_at', target_session.created_at
  );
end;
$$;
revoke execute on function public.end_house_session(uuid) from public, anon, authenticated;
grant execute on function public.end_house_session(uuid) to authenticated;
commit;
