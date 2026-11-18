-- Run entire script after migration 006. Fixtures and all changes roll back.
begin;
insert into auth.users(id) values
 ('00000000-0000-4000-8000-000000000061'),
 ('00000000-0000-4000-8000-000000000062'),
 ('00000000-0000-4000-8000-000000000063');
insert into public.house_members(user_id,role) values
 ('00000000-0000-4000-8000-000000000061','admin'),
 ('00000000-0000-4000-8000-000000000062','member');
update public.house_sessions set status='inactive',current_bill_id=null where status='active';
insert into public.house_bills(id,title) values
 ('00000000-0000-4000-8000-000000000064','First test bill'),
 ('00000000-0000-4000-8000-000000000065','Second test bill'),
 ('00000000-0000-4000-8000-000000000066','Finalized test bill');
insert into public.house_sessions(id,status) values
 ('00000000-0000-4000-8000-000000000067','active'),
 ('00000000-0000-4000-8000-000000000068','ended');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000061"}',true);
do $$ declare result jsonb; begin
 result := public.present_house_bill('00000000-0000-4000-8000-000000000067','00000000-0000-4000-8000-000000000064');
 if result->>'current_bill_id' is distinct from '00000000-0000-4000-8000-000000000064' then raise exception 'Bill not presented'; end if;
 if public.get_house_state()->'session' is distinct from result then raise exception 'Snapshot mismatch'; end if;
 if public.get_house_state()->'ballot' is distinct from 'null'::jsonb then raise exception 'Presentation created ballot'; end if;
 begin
  perform public.present_house_bill(null,'00000000-0000-4000-8000-000000000064');
  raise exception 'Null session accepted';
 exception when invalid_parameter_value then null; end;
 begin
  perform public.present_house_bill('00000000-0000-4000-8000-000000000067',null);
  raise exception 'Null bill accepted';
 exception when invalid_parameter_value then null; end;
 begin
  perform public.present_house_bill('00000000-0000-4000-8000-000000000069','00000000-0000-4000-8000-000000000064');
  raise exception 'Missing session accepted';
 exception when no_data_found then null; end;
 begin
  perform public.present_house_bill('00000000-0000-4000-8000-000000000068','00000000-0000-4000-8000-000000000064');
  raise exception 'Ended session accepted';
 exception when object_not_in_prerequisite_state then null; end;
end $$;
reset role;
insert into public.house_ballots(id,session_id,bill_id,status) values
 ('00000000-0000-4000-8000-000000000070','00000000-0000-4000-8000-000000000067','00000000-0000-4000-8000-000000000064','open'),
 ('00000000-0000-4000-8000-000000000071','00000000-0000-4000-8000-000000000067','00000000-0000-4000-8000-000000000066','finalized');
insert into public.house_votes(ballot_id,member_id,choice) values
 ('00000000-0000-4000-8000-000000000070','00000000-0000-4000-8000-000000000062','Yea');
set local role authenticated;
do $$ begin
 -- A retry must leave the current open ballot open.
 perform public.present_house_bill('00000000-0000-4000-8000-000000000067','00000000-0000-4000-8000-000000000064');
 if public.get_house_state()->'ballot'->>'status' is distinct from 'open' then raise exception 'Retry closed voting'; end if;
 -- Invalid target must not close the old ballot or change the display.
 begin
  perform public.present_house_bill('00000000-0000-4000-8000-000000000067','00000000-0000-4000-8000-000000000069');
  raise exception 'Missing bill accepted';
 exception when no_data_found then null; end;
 if public.get_house_state()->'ballot'->>'status' is distinct from 'open' then raise exception 'Failed switch changed ballot'; end if;
 perform public.present_house_bill('00000000-0000-4000-8000-000000000067','00000000-0000-4000-8000-000000000065');
end $$;
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000062"}',true);
do $$ declare result jsonb; begin
 result := public.get_house_state();
 if jsonb_array_length(result->'bills') <> 1 or result->'bills'->0->>'id' is distinct from '00000000-0000-4000-8000-000000000065' then raise exception 'Member visibility incorrect'; end if;
 begin
  perform public.present_house_bill('00000000-0000-4000-8000-000000000067','00000000-0000-4000-8000-000000000064');
  raise exception 'Member could present';
 exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000063","user_metadata":{"role":"admin"}}',true);
do $$ begin
 begin
  perform public.present_house_bill('00000000-0000-4000-8000-000000000067','00000000-0000-4000-8000-000000000064');
  raise exception 'Unapproved user could present';
 exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claims','{}',true);
do $$ begin
 begin
  perform public.present_house_bill('00000000-0000-4000-8000-000000000067','00000000-0000-4000-8000-000000000064');
  raise exception 'Missing identity could present';
 exception when insufficient_privilege then null; end;
end $$;
reset role;
do $$ begin
 if (select status from public.house_ballots where id='00000000-0000-4000-8000-000000000070') is distinct from 'closed' then raise exception 'Old ballot still open'; end if;
 if (select status from public.house_ballots where id='00000000-0000-4000-8000-000000000071') is distinct from 'finalized' then raise exception 'Finalized ballot changed'; end if;
 if (select choice from public.house_votes where ballot_id='00000000-0000-4000-8000-000000000070' and member_id='00000000-0000-4000-8000-000000000062') is distinct from 'Yea' then raise exception 'Vote lost'; end if;
 if exists(select 1 from public.house_ballots where session_id='00000000-0000-4000-8000-000000000067' and bill_id='00000000-0000-4000-8000-000000000065') then raise exception 'Switch created a ballot'; end if;
end $$;
set local role anon;
do $$ begin
 begin
  perform public.present_house_bill('00000000-0000-4000-8000-000000000067','00000000-0000-4000-8000-000000000064');
  raise exception 'Anonymous user could present';
 exception when insufficient_privilege then null; end;
end $$;
reset role;
rollback;
