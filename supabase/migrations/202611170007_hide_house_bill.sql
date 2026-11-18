-- Return members to waiting without ending the meeting or deleting records.
begin;
create or replace function public.hide_house_bill(p_session_id uuid)
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
  perform pg_catalog.pg_advisory_xact_lock(712804, 1);
  select s.* into target_session from public.house_sessions s
    where s.id = p_session_id for update;
  if not found then
    raise exception 'Session not found' using errcode = 'P0002';
  end if;
  if target_session.status <> 'active' then
    raise exception 'Session is not active' using errcode = '55000';
  end if;

  -- Match the lifecycle/session/ballot lock order of present and end.
  perform b.id from public.house_ballots b
    where b.session_id = p_session_id order by b.id for update;
  update public.house_ballots set status = 'closed'
    where session_id = p_session_id and status = 'open';

  if target_session.current_bill_id is not null then
    update public.house_sessions set current_bill_id = null
      where id = p_session_id returning * into target_session;
  end if;

  return jsonb_build_object(
    'id', target_session.id,
    'status', target_session.status,
    'current_bill_id', target_session.current_bill_id,
    'created_at', target_session.created_at
  );
end;
$$;
revoke execute on function public.hide_house_bill(uuid) from public, anon, authenticated;
grant execute on function public.hide_house_bill(uuid) to authenticated;
commit;
