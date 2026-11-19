begin;
-- Maintained by trusted admins via SQL/CSV, never publicly readable or writable.
create table house_private.email_roster (
  email text primary key check (email = lower(btrim(email)) and email ~ '^[^[:space:]@]+@gatech[.]edu$'),
  claimed_by uuid unique references auth.users(id) on delete set null
);
alter table house_private.email_roster enable row level security;
revoke all on house_private.email_roster from public, anon, authenticated;

create or replace function public.claim_house_membership()
returns boolean
language plpgsql volatile security definer
set search_path = ''
as $$
declare
  caller uuid := auth.uid();
  verified_email text;
  claim_owner uuid;
begin
  if caller is null then
    raise exception 'Sign in required' using errcode = '42501';
  end if;
  -- Read Auth's verified identity, not user-editable metadata or supplied email.
  select lower(btrim(u.email)) into verified_email from auth.users u
    where u.id = caller and u.email_confirmed_at is not null;
  if verified_email is null then return false; end if;
  -- Preserve manually assigned memberships, especially existing admins.
  if exists(select 1 from public.house_members m where m.user_id = caller) then return true; end if;
  select r.claimed_by into claim_owner from house_private.email_roster r
    where r.email = verified_email for update;
  if not found or (claim_owner is not null and claim_owner <> caller) then return false; end if;
  insert into public.house_members(user_id,role) values(caller,'member') on conflict(user_id) do nothing;
  update house_private.email_roster set claimed_by = caller where email = verified_email;
  return true;
end;
$$;
revoke execute on function public.claim_house_membership() from public, anon, authenticated;
grant execute on function public.claim_house_membership() to authenticated;
commit;
