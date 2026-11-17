-- Permission helpers only. Does not grant access to bills, sessions, or votes.
begin;
create schema if not exists house_private;
revoke all on schema house_private from public, anon, authenticated;
grant usage on schema house_private to authenticated;

-- A private schema keeps these helpers out of the public Data API.
-- Definer access avoids membership-policy recursion when reused in future RLS.
-- No caller-supplied user ID or role is accepted.
create or replace function house_private.is_member()
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.house_members m
    where m.user_id = (select auth.uid())
      and m.role in ('member', 'admin')
  );
$$;

create or replace function house_private.is_admin()
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.house_members m
    where m.user_id = (select auth.uid()) and m.role = 'admin'
  );
$$;

create or replace function house_private.require_member()
returns void
language plpgsql stable security invoker
set search_path = ''
as $$
begin
  if not house_private.is_member() then
    raise exception 'Approved membership required' using errcode = '42501';
  end if;
end;
$$;

create or replace function house_private.require_admin()
returns void
language plpgsql stable security invoker
set search_path = ''
as $$
begin
  if not house_private.is_admin() then
    raise exception 'Admin access required' using errcode = '42501';
  end if;
end;
$$;

revoke execute on function house_private.is_member() from public, anon, authenticated;
revoke execute on function house_private.is_admin() from public, anon, authenticated;
revoke execute on function house_private.require_member() from public, anon, authenticated;
revoke execute on function house_private.require_admin() from public, anon, authenticated;
grant execute on function house_private.is_member() to authenticated;
grant execute on function house_private.is_admin() to authenticated;
grant execute on function house_private.require_member() to authenticated;
grant execute on function house_private.require_admin() to authenticated;
commit;
