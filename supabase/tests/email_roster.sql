-- Run whole script after migration 009; all fixtures roll back.
begin;
insert into auth.users(id,email,email_confirmed_at) values
 ('00000000-0000-4000-8000-000000000101','roster-test-101@gatech.edu',now()),
 ('00000000-0000-4000-8000-000000000102','roster-test-102@gatech.edu',null),
 ('00000000-0000-4000-8000-000000000103','roster-test-103@gatech.edu',now()),
 ('00000000-0000-4000-8000-000000000104','roster-test-104@gatech.edu',now());
insert into house_private.email_roster(email) values('roster-test-101@gatech.edu'),('roster-test-102@gatech.edu');
insert into public.house_members(user_id,role) values('00000000-0000-4000-8000-000000000104','admin');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000101"}',true);
do $$ begin
 if not public.claim_house_membership() or not public.claim_house_membership() then raise exception 'Verified roster claim failed'; end if;
 if not exists(select 1 from public.house_members where user_id=auth.uid() and role='member') then raise exception 'Wrong role assigned'; end if;
 begin
  perform email from house_private.email_roster;
  raise exception 'Roster exposed';
 exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000102"}',true);
do $$ begin
 if public.claim_house_membership() then raise exception 'Unverified email claimed'; end if;
end $$;
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000103","email":"roster-test-101@gatech.edu","user_metadata":{"role":"admin"}}',true);
do $$ begin
 if public.claim_house_membership() then raise exception 'Non-roster or spoofed email claimed'; end if;
end $$;
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000104"}',true);
do $$ begin
 if not public.claim_house_membership() or not house_private.is_admin() then raise exception 'Existing admin changed'; end if;
end $$;
select set_config('request.jwt.claims','{}',true);
do $$ begin
 begin
  perform public.claim_house_membership();
  raise exception 'Missing identity claimed';
 exception when insufficient_privilege then null; end;
end $$;
reset role;
set local role anon;
do $$ begin
 begin
  perform public.claim_house_membership();
  raise exception 'Anonymous claimed';
 exception when insufficient_privilege then null; end;
end $$;
reset role;
rollback;
