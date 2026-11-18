-- Private invalidations only: no document content or individual votes in events.
begin;
create policy house_session_broadcast_receive
on realtime.messages for select to authenticated
using (
  realtime.topic() = 'house:session'
  and extension = 'broadcast'
  and house_private.is_member()
);

create or replace function house_private.notify_session_changed()
returns trigger
language plpgsql security definer
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE' and new is not distinct from old then
    return null;
  end if;
  perform realtime.send('{}'::jsonb, 'state_changed', 'house:session', true);
  return null;
end;
$$;
revoke execute on function house_private.notify_session_changed() from public, anon, authenticated;
create trigger house_session_changed
  after insert or update or delete on public.house_sessions
  for each row execute function house_private.notify_session_changed();
commit;
