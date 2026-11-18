-- Run entire script after migration 007. All test changes roll back.
begin;
insert into auth.users(id) values
 ('00000000-0000-4000-8000-000000000081'),
 ('00000000-0000-4000-8000-000000000082'),
 ('00000000-0000-4000-8000-000000000083');
insert into public.house_members(user_id,role) values
 ('00000000-0000-4000-8000-000000000081','admin'),
 ('00000000-0000-4000-8000-000000000082','member');
update public.house_sessions set status='inactive',current_bill_id=null where status='active';
insert into public.house_bills(id,title) values
 ('00000000-0000-4000-8000-000000000084','Hide test bill'),
 ('00000000-0000-4000-8000-000000000085','Finalized test bill');
insert into public.house_sessions(id,status,current_bill_id) values
 ('00000000-0000-4000-8000-000000000086','active','00000000-0000-4000-8000-000000000084'),
 ('00000000-0000-4000-8000-000000000087','ended',null);
insert into public.house_ballots(id,session_id,bill_id,status) values
 ('00000000-0000-4000-8000-000000000088','00000000-0000-4000-8000-000000000086','00000000-0000-4000-8000-000000000084','open'),
 ('00000000-0000-4000-8000-000000000089','00000000-0000-4000-8000-000000000086','00000000-0000-4000-8000-000000000085','finalized');
insert into public.house_votes(ballot_id,member_id,choice) values
 ('00000000-0000-4000-8000-000000000088','00000000-0000-4000-8000-000000000082','Yea');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000082"}',true);
do $$ begin
 begin
  perform public.hide_house_bill('00000000-0000-4000-8000-000000000086');
  raise exception 'Member could hide bill';
 exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000083","user_metadata":{"role":"admin"}}',true);
do $$ begin
 begin
  perform public.hide_house_bill('00000000-0000-4000-8000-000000000086');
  raise exception 'Unapproved user could hide bill';
 exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claims','{}',true);
do $$ begin
 begin
  perform public.hide_house_bill('00000000-0000-4000-8000-000000000086');
  raise exception 'Missing identity could hide bill';
 exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000081"}',true);
do $$ declare result jsonb; begin
 begin
  perform public.hide_house_bill(null);
  raise exception 'Null ID accepted';
 exception when invalid_parameter_value then null; end;
 begin
  perform public.hide_house_bill('00000000-0000-4000-8000-000000000090');
  raise exception 'Missing session accepted';
 exception when no_data_found then null; end;
 begin
  perform public.hide_house_bill('00000000-0000-4000-8000-000000000087');
  raise exception 'Ended session accepted';
 exception when object_not_in_prerequisite_state then null; end;
 if public.get_house_state()->'session'->>'current_bill_id' is distinct from '00000000-0000-4000-8000-000000000084' then
  raise exception 'Rejected commands changed presentation'; end if;
 result := public.hide_house_bill('00000000-0000-4000-8000-000000000086');
 if result->>'status' is distinct from 'active' or result->'current_bill_id' is distinct from 'null'::jsonb then
  raise exception 'Session not left active and waiting'; end if;
 if public.hide_house_bill('00000000-0000-4000-8000-000000000086') is distinct from result then
  raise exception 'Repeated hide changed session'; end if;
end $$;
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000082"}',true);
do $$ declare result jsonb; begin
 result := public.get_house_state();
 if result->'session'->>'status' is distinct from 'active' or result->'bills' is distinct from '[]'::jsonb or result->'ballot' is distinct from 'null'::jsonb then
  raise exception 'Member waiting state incorrect'; end if;
end $$;
reset role;
do $$ begin
 if (select status from public.house_ballots where id='00000000-0000-4000-8000-000000000088') is distinct from 'closed' then raise exception 'Voting not closed'; end if;
 if (select status from public.house_ballots where id='00000000-0000-4000-8000-000000000089') is distinct from 'finalized' then raise exception 'Finalized result changed'; end if;
 if (select choice from public.house_votes where ballot_id='00000000-0000-4000-8000-000000000088' and member_id='00000000-0000-4000-8000-000000000082') is distinct from 'Yea' then raise exception 'Vote lost'; end if;
 if not exists(select 1 from public.house_bills where id='00000000-0000-4000-8000-000000000084') then raise exception 'Bill deleted'; end if;
end $$;
set local role anon;
do $$ begin
 begin
  perform public.hide_house_bill('00000000-0000-4000-8000-000000000086');
  raise exception 'Anonymous caller could hide bill';
 exception when insufficient_privilege then null; end;
end $$;
reset role;
rollback;
