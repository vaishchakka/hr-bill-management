-- One authorized snapshot; raw table access remains locked down.
begin;
create or replace function public.get_house_state()
returns jsonb
language plpgsql stable security definer
set search_path = ''
as $$
declare
  admin_user boolean;
  active_session public.house_sessions%rowtype;
  visible_bills jsonb;
  current_ballot jsonb;
begin
  perform house_private.require_member();
  admin_user := house_private.is_admin();

  select s.* into active_session
  from public.house_sessions s where s.status = 'active';

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', b.id, 'title', b.title, 'body', b.body,
    'status', b.status, 'created_at', b.created_at
  ) order by b.created_at, b.id), '[]'::jsonb)
  into visible_bills
  from public.house_bills b
  where admin_user or b.id = active_session.current_bill_id;

  select jsonb_build_object('id', v.id, 'status', v.status,
    'bill_id', v.bill_id, 'session_id', v.session_id)
  into current_ballot
  from public.house_ballots v
  where v.session_id = active_session.id
    and v.bill_id = active_session.current_bill_id;

  return jsonb_build_object(
    'role', case when admin_user then 'admin' else 'member' end,
    'session', case when active_session.id is null then null else
      jsonb_build_object('id', active_session.id, 'status', active_session.status,
        'current_bill_id', active_session.current_bill_id,
        'created_at', active_session.created_at) end,
    'bills', visible_bills,
    'ballot', current_ballot
  );
end;
$$;
revoke execute on function public.get_house_state() from public, anon, authenticated;
grant execute on function public.get_house_state() to authenticated;
commit;
