-- Run the ENTIRE script in SQL Editor after migration 004.
-- All fixture changes roll back, including temporary deactivation of any session.
begin;
insert into auth.users (id) values
 ('00000000-0000-4000-8000-000000000041'),
 ('00000000-0000-4000-8000-000000000042'),
 ('00000000-0000-4000-8000-000000000043');
insert into public.house_members (user_id, role) values
 ('00000000-0000-4000-8000-000000000041', 'admin'),
 ('00000000-0000-4000-8000-000000000042', 'member');
update public.house_sessions set status = 'inactive', current_bill_id = null where status = 'active';
insert into public.house_bills (id, title) values
 ('00000000-0000-4000-8000-000000000044', 'Session test bill');
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-000000000041"}', true);
do $$ declare first_start jsonb; second_start jsonb; snapshot jsonb; begin
 first_start := public.start_house_session();
 second_start := public.start_house_session();
 if first_start is distinct from second_start then raise exception 'Repeated start changed session'; end if;
 if first_start->>'status' is distinct from 'active'
    or first_start->'current_bill_id' is distinct from 'null'::jsonb
    or first_start->>'id' is null then raise exception 'Invalid initial session'; end if;
 snapshot := public.get_house_state();
 if snapshot->'session' is distinct from first_start then raise exception 'Snapshot does not match started session'; end if;
 if snapshot->'ballot' is distinct from 'null'::jsonb then raise exception 'Starting opened a ballot'; end if;
end $$;
reset role;
do $$ begin
 if (select count(*) from public.house_sessions where status = 'active') <> 1 then
   raise exception 'Expected exactly one active session';
 end if;
end $$;
-- Simulate a later presentation; another start must preserve it.
update public.house_sessions set current_bill_id = '00000000-0000-4000-8000-000000000044' where status = 'active';
set local role authenticated;
do $$ declare result jsonb; begin
 result := public.start_house_session();
 if result->>'current_bill_id' is distinct from '00000000-0000-4000-8000-000000000044' then
   raise exception 'Repeated start cleared presentation';
 end if;
end $$;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-000000000042"}', true);
do $$ begin
 begin
   perform public.start_house_session();
   raise exception 'Member could start a session';
 exception when insufficient_privilege then null;
 end;
 begin
   insert into public.house_sessions(status) values ('active');
   raise exception 'Member could write sessions directly';
 exception when insufficient_privilege then null;
 end;
end $$;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-000000000043","user_metadata":{"role":"admin"}}', true);
do $$ begin
 begin
   perform public.start_house_session();
   raise exception 'Unapproved user could start a session';
 exception when insufficient_privilege then null;
 end;
end $$;
select set_config('request.jwt.claims', '{}', true);
do $$ begin
 begin
   perform public.start_house_session();
   raise exception 'Missing identity could start a session';
 exception when insufficient_privilege then null;
 end;
end $$;
reset role;
set local role anon;
do $$ begin
 begin
   perform public.start_house_session();
   raise exception 'Anonymous caller could start a session';
 exception when insufficient_privilege then null;
 end;
end $$;
reset role;
rollback;
