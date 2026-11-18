-- Run the whole script after migration 005. Everything rolls back.
begin;
insert into auth.users(id) values
 ('00000000-0000-4000-8000-000000000051'),
 ('00000000-0000-4000-8000-000000000052'),
 ('00000000-0000-4000-8000-000000000053');
insert into public.house_members(user_id,role) values
 ('00000000-0000-4000-8000-000000000051','admin'),
 ('00000000-0000-4000-8000-000000000052','member');
update public.house_sessions set status='inactive',current_bill_id=null where status='active';
insert into public.house_bills(id,title) values
 ('00000000-0000-4000-8000-000000000054','End session test'),
 ('00000000-0000-4000-8000-000000000055','Finalized test');
insert into public.house_sessions(id,status,current_bill_id) values
 ('00000000-0000-4000-8000-000000000056','active','00000000-0000-4000-8000-000000000054');
insert into public.house_ballots(id,session_id,bill_id,status) values
 ('00000000-0000-4000-8000-000000000057','00000000-0000-4000-8000-000000000056','00000000-0000-4000-8000-000000000054','open'),
 ('00000000-0000-4000-8000-000000000058','00000000-0000-4000-8000-000000000056','00000000-0000-4000-8000-000000000055','finalized');
insert into public.house_votes(ballot_id,member_id,choice) values
 ('00000000-0000-4000-8000-000000000057','00000000-0000-4000-8000-000000000052','Yea');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000052"}',true);
do $$ begin
 begin
  perform public.end_house_session('00000000-0000-4000-8000-000000000056');
  raise exception 'Member ended session';
 exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000053","user_metadata":{"role":"admin"}}',true);
do $$ begin
 begin
  perform public.end_house_session('00000000-0000-4000-8000-000000000056');
  raise exception 'Unapproved user ended session';
 exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claims','{}',true);
do $$ begin
 begin
  perform public.end_house_session('00000000-0000-4000-8000-000000000056');
  raise exception 'Missing identity ended session';
 exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000051"}',true);
do $$ declare result jsonb; begin
 result := public.end_house_session('00000000-0000-4000-8000-000000000056');
 if result->>'status' is distinct from 'ended' or result->'current_bill_id' is distinct from 'null'::jsonb then
  raise exception 'Session did not end correctly'; end if;
 if result is distinct from public.end_house_session('00000000-0000-4000-8000-000000000056') then
  raise exception 'Repeated end changed session'; end if;
 if public.get_house_state()->'session' is distinct from 'null'::jsonb then
  raise exception 'Ended session still visible'; end if;
 begin
  perform public.end_house_session(null);
  raise exception 'Null ID accepted';
 exception when invalid_parameter_value then null; end;
 begin
  perform public.end_house_session('00000000-0000-4000-8000-000000000059');
  raise exception 'Unknown session accepted';
 exception when no_data_found then null; end;
 -- Ending an old session must leave a newer active one untouched.
 result := public.start_house_session();
 perform public.end_house_session('00000000-0000-4000-8000-000000000056');
 if public.get_house_state()->'session' is distinct from result then
  raise exception 'Old request affected new session'; end if;
end $$;
reset role;
do $$ begin
 if (select status from public.house_ballots where id='00000000-0000-4000-8000-000000000057') is distinct from 'closed' then
  raise exception 'Open ballot not closed'; end if;
 if (select status from public.house_ballots where id='00000000-0000-4000-8000-000000000058') is distinct from 'finalized' then
  raise exception 'Finalized ballot changed'; end if;
 if (select choice from public.house_votes where ballot_id='00000000-0000-4000-8000-000000000057' and member_id='00000000-0000-4000-8000-000000000052') is distinct from 'Yea' then
  raise exception 'Vote lost'; end if;
 if not exists(select 1 from public.house_bills where id='00000000-0000-4000-8000-000000000054') then
  raise exception 'Bill lost'; end if;
end $$;
set local role anon;
do $$ begin
 begin
  perform public.end_house_session('00000000-0000-4000-8000-000000000056');
  raise exception 'Anonymous caller ended session';
 exception when insufficient_privilege then null; end;
end $$;
reset role;
rollback;
