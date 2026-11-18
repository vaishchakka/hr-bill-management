-- Presenting changes the shared display, never opens voting.
begin;
create or replace function public.present_house_bill(p_session_id uuid, p_bill_id uuid)
returns jsonb
language plpgsql volatile security definer
set search_path = ''
as $$
declare
  target_session public.house_sessions%rowtype;
begin
  perform house_private.require_admin();
  if p_session_id is null or p_bill_id is null then
    raise exception 'Session ID and bill ID are required' using errcode = '22023';
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

  -- Keep the selected document from being deleted/changed during this command.
  perform b.id from public.house_bills b where b.id = p_bill_id for share;
  if not found then
    raise exception 'Bill not found' using errcode = 'P0002';
  end if;

  if target_session.current_bill_id is distinct from p_bill_id then
    -- Same session-before-ballot lock order as end_session. Close any open
    -- ballot in this session, including a previously hidden one.
    perform v.id from public.house_ballots v
      where v.session_id = p_session_id order by v.id for update;
    update public.house_ballots set status = 'closed'
      where session_id = p_session_id and status = 'open';
    update public.house_sessions set current_bill_id = p_bill_id
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
revoke execute on function public.present_house_bill(uuid, uuid) from public, anon, authenticated;
grant execute on function public.present_house_bill(uuid, uuid) to authenticated;
commit;
