-- Run after migration 002 in SQL Editor as postgres. All fixtures roll back.
-- Uses temporary test identities, never modifies existing accounts.
begin;
insert into auth.users (id) values
 ('00000000-0000-4000-8000-000000000001'),
 ('00000000-0000-4000-8000-000000000002'),
 ('00000000-0000-4000-8000-000000000003');
insert into public.house_members (user_id, role) values
 ('00000000-0000-4000-8000-000000000001', 'admin'),
 ('00000000-0000-4000-8000-000000000002', 'member');
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-000000000001","role":"authenticated"}', true);
do $$ begin
 if not house_private.is_admin() or not house_private.is_member() then raise exception 'Admin check failed'; end if;
 perform house_private.require_admin();
 perform house_private.require_member();
end $$;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-000000000002","role":"authenticated"}', true);
do $$ begin
 if house_private.is_admin() or not house_private.is_member() then raise exception 'Member check failed'; end if;
 perform house_private.require_member();
 begin
   perform house_private.require_admin();
   raise exception 'Member incorrectly passed admin check';
 exception when insufficient_privilege then null;
 end;
 -- Table writes remain forbidden: membership cannot be self-promoted.
 begin
   update public.house_members set role = 'admin' where user_id = auth.uid();
   raise exception 'Member could write role';
 exception when insufficient_privilege then null;
 end;
end $$;
-- Forged metadata cannot grant membership or admin rights.
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-000000000003","role":"authenticated","user_metadata":{"role":"admin"}}', true);
do $$ begin
 if house_private.is_member() or house_private.is_admin() then raise exception 'Unapproved user passed'; end if;
 begin
   perform house_private.require_member();
   raise exception 'Unapproved user passed guard';
 exception when insufficient_privilege then null;
 end;
end $$;
select set_config('request.jwt.claims', '{}', true);
do $$ begin
 if house_private.is_member() or house_private.is_admin() then raise exception 'Missing identity passed'; end if;
end $$;
reset role;
do $$ begin
 if has_schema_privilege('anon', 'house_private', 'USAGE') then raise exception 'Anonymous schema access'; end if;
 if has_function_privilege('anon', 'house_private.is_admin()', 'EXECUTE') then raise exception 'Anonymous helper access'; end if;
end $$;
rollback;
-- Successful execution means all assertions passed; fixtures were discarded.
