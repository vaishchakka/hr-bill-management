-- Initial schema only. No anonymous access or client writes are permitted.
-- Voting/session command RPCs and their tests will be added before enabling writes.
begin;
create table public.house_members (
  user_id uuid primary key references auth.users(id) on delete cascade,
  role text not null default 'member' check (role in ('member', 'admin')),
  created_at timestamptz not null default now()
);
create table public.house_bills (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  body text not null default '',
  status text not null default 'draft' check (status in ('draft', 'ready', 'passed', 'failed')),
  created_at timestamptz not null default now()
);
create table public.house_sessions (
  id uuid primary key default gen_random_uuid(),
  status text not null default 'inactive' check (status in ('inactive', 'active', 'ended')),
  current_bill_id uuid references public.house_bills(id),
  created_at timestamptz not null default now(),
  check (status = 'active' or current_bill_id is null)
);
create unique index one_active_house_session on public.house_sessions ((status)) where status = 'active';
create table public.house_ballots (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references public.house_sessions(id),
  bill_id uuid not null references public.house_bills(id),
  status text not null default 'closed' check (status in ('closed', 'open', 'finalized')),
  unique(session_id, bill_id)
);
create table public.house_votes (
  ballot_id uuid not null references public.house_ballots(id),
  member_id uuid not null references public.house_members(user_id),
  choice text not null check (choice in ('Yea', 'Nay', 'Abstain')),
  updated_at timestamptz not null default now(),
  primary key (ballot_id, member_id)
);
-- Deny by default until authenticated reads and transactional command RPCs exist.
alter table public.house_members enable row level security;
alter table public.house_bills enable row level security;
alter table public.house_sessions enable row level security;
alter table public.house_ballots enable row level security;
alter table public.house_votes enable row level security;
revoke all on public.house_members, public.house_bills, public.house_sessions, public.house_ballots, public.house_votes from anon, authenticated;
-- Users may inspect only their own assigned membership. They cannot assign roles.
grant select on public.house_members to authenticated;
create policy own_membership on public.house_members for select to authenticated using (user_id = (select auth.uid()));
commit;
