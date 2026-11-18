-- Run the entire script in SQL Editor after migration 003.
-- All changes, including temporarily hiding any existing session, roll back.
begin;
insert into auth.users (id) values
 ('00000000-0000-4000-8000-000000000011'),
 ('00000000-0000-4000-8000-000000000012'),
 ('00000000-0000-4000-8000-000000000013');
insert into public.house_members (user_id, role) values
 ('00000000-0000-4000-8000-000000000011', 'admin'),
 ('00000000-0000-4000-8000-000000000012', 'member');
update public.house_sessions set status = 'inactive', current_bill_id = null where status = 'active';
insert into public.house_bills (id, title) values
 ('00000000-0000-4000-8000-000000000021', 'Visible test bill'),
 ('00000000-0000-4000-8000-000000000022', 'Hidden test bill');
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-000000000012"}', true);
do $$ declare result jsonb; begin
 result := public.get_house_state();
 if result->'session' <> 'null'::jsonb or result->'bills' <> '[]'::jsonb or result->'ballot' <> 'null'::jsonb then
   raise exception 'Inactive state leaked data';
 end if;
end $$;
reset role;
insert into public.house_sessions (id, status, current_bill_id) values
 ('00000000-0000-4000-8000-000000000031', 'active', '00000000-0000-4000-8000-000000000021');
insert into public.house_ballots (session_id, bill_id, status) values
 ('00000000-0000-4000-8000-000000000031', '00000000-0000-4000-8000-000000000021', 'open');
set local role authenticated;
do $$ declare result jsonb; begin
 result := public.get_house_state();
 if result->>'role' <> 'member' or jsonb_array_length(result->'bills') <> 1
    or result->'bills'->0->>'id' <> '00000000-0000-4000-8000-000000000021'
    or result->'ballot'->>'status' <> 'open' then
   raise exception 'Member snapshot incorrect';
 end if;
 if result ? 'votes' then raise exception 'Unexpected vote data'; end if;
 begin
   perform id from public.house_bills;
   raise exception 'Member has raw bill access';
 exception when insufficient_privilege then null;
 end;
end $$;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-000000000011"}', true);
do $$ declare result jsonb; begin
 result := public.get_house_state();
 if result->>'role' <> 'admin' or not exists (
   select 1 from jsonb_array_elements(result->'bills') b
   where b->>'id' = '00000000-0000-4000-8000-000000000022'
 ) then raise exception 'Admin cannot see hidden bill'; end if;
end $$;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-000000000013","user_metadata":{"role":"admin"}}', true);
do $$ begin
 begin
   perform public.get_house_state();
   raise exception 'Unapproved account read state';
 exception when insufficient_privilege then null;
 end;
end $$;
select set_config('request.jwt.claims', '{}', true);
do $$ begin
 begin
   perform public.get_house_state();
   raise exception 'Missing identity read state';
 exception when insufficient_privilege then null;
 end;
end $$;
reset role;
-- Active session with no presentation must not expose bill or ballot to member.
update public.house_sessions set current_bill_id = null where id = '00000000-0000-4000-8000-000000000031';
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-000000000012"}', true);
do $$ declare result jsonb; begin
 result := public.get_house_state();
 if result->'session' = 'null'::jsonb or result->'bills' <> '[]'::jsonb
    or result->'ballot' <> 'null'::jsonb then raise exception 'Waiting state incorrect'; end if;
end $$;
reset role;
do $$ begin
 if has_function_privilege('anon', 'public.get_house_state()', 'EXECUTE') then
   raise exception 'Anonymous snapshot access';
 end if;
end $$;
rollback;
