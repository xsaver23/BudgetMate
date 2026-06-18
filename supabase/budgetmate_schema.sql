create table if not exists public.budget_members (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  display_name text not null,
  email text,
  initials text not null,
  color text not null,
  role text not null check (role in ('owner', 'member')),
  invite_status text not null check (invite_status in ('active', 'invited', 'pending')),
  joined_date timestamptz,
  created_date timestamptz not null,
  updated_at timestamptz not null default now()
);

create table if not exists public.budget_transactions (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null,
  amount numeric not null check (amount >= 0),
  type text not null check (type in ('income', 'expense')),
  category text not null,
  payment_method text,
  created_by_member_id uuid not null,
  date timestamptz not null,
  created_at timestamptz not null,
  recurrence_rule text,
  splits jsonb not null default '[]'::jsonb,
  updated_at timestamptz not null default now()
);

create table if not exists public.budget_settlements (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  from_member_id uuid not null,
  to_member_id uuid not null,
  amount numeric not null check (amount > 0),
  date timestamptz not null,
  updated_at timestamptz not null default now()
);

alter table public.budget_members enable row level security;
alter table public.budget_transactions enable row level security;
alter table public.budget_settlements enable row level security;

drop policy if exists "Users can read their budget members" on public.budget_members;
create policy "Users can read their budget members"
on public.budget_members
for select
to authenticated
using (auth.uid() = user_id);

drop policy if exists "Users can insert their budget members" on public.budget_members;
create policy "Users can insert their budget members"
on public.budget_members
for insert
to authenticated
with check (auth.uid() = user_id);

drop policy if exists "Users can update their budget members" on public.budget_members;
create policy "Users can update their budget members"
on public.budget_members
for update
to authenticated
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

drop policy if exists "Users can delete their budget members" on public.budget_members;
create policy "Users can delete their budget members"
on public.budget_members
for delete
to authenticated
using (auth.uid() = user_id);

drop policy if exists "Users can read their budget transactions" on public.budget_transactions;
create policy "Users can read their budget transactions"
on public.budget_transactions
for select
to authenticated
using (auth.uid() = user_id);

drop policy if exists "Users can insert their budget transactions" on public.budget_transactions;
create policy "Users can insert their budget transactions"
on public.budget_transactions
for insert
to authenticated
with check (auth.uid() = user_id);

drop policy if exists "Users can update their budget transactions" on public.budget_transactions;
create policy "Users can update their budget transactions"
on public.budget_transactions
for update
to authenticated
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

drop policy if exists "Users can delete their budget transactions" on public.budget_transactions;
create policy "Users can delete their budget transactions"
on public.budget_transactions
for delete
to authenticated
using (auth.uid() = user_id);

drop policy if exists "Users can read their budget settlements" on public.budget_settlements;
create policy "Users can read their budget settlements"
on public.budget_settlements
for select
to authenticated
using (auth.uid() = user_id);

drop policy if exists "Users can insert their budget settlements" on public.budget_settlements;
create policy "Users can insert their budget settlements"
on public.budget_settlements
for insert
to authenticated
with check (auth.uid() = user_id);

drop policy if exists "Users can update their budget settlements" on public.budget_settlements;
create policy "Users can update their budget settlements"
on public.budget_settlements
for update
to authenticated
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

drop policy if exists "Users can delete their budget settlements" on public.budget_settlements;
create policy "Users can delete their budget settlements"
on public.budget_settlements
for delete
to authenticated
using (auth.uid() = user_id);

-- Migration: add account-level budget settings sync.
create table if not exists public.budget_settings (
  user_id uuid primary key references auth.users(id) on delete cascade,
  monthly_budget numeric not null default 0 check (monthly_budget >= 0),
  currency_code text not null default 'USD',
  appearance text not null default 'system' check (appearance in ('system', 'light', 'dark')),
  category_budgets jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

alter table public.budget_settings enable row level security;

drop policy if exists "Users can read their budget settings" on public.budget_settings;
create policy "Users can read their budget settings"
on public.budget_settings
for select
to authenticated
using (auth.uid() = user_id);

drop policy if exists "Users can insert their budget settings" on public.budget_settings;
create policy "Users can insert their budget settings"
on public.budget_settings
for insert
to authenticated
with check (auth.uid() = user_id);

drop policy if exists "Users can update their budget settings" on public.budget_settings;
create policy "Users can update their budget settings"
on public.budget_settings
for update
to authenticated
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

drop policy if exists "Users can delete their budget settings" on public.budget_settings;
create policy "Users can delete their budget settings"
on public.budget_settings
for delete
to authenticated
using (auth.uid() = user_id);

-- Migration: add household budget foundation.
create table if not exists public.budgets (
  id uuid primary key,
  owner_user_id uuid not null references auth.users(id) on delete cascade,
  name text not null default 'My Budget',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.budget_memberships (
  budget_id uuid not null references public.budgets(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null default 'owner' check (role in ('owner', 'member')),
  status text not null default 'active' check (status in ('active', 'invited', 'pending')),
  created_at timestamptz not null default now(),
  primary key (budget_id, user_id)
);

alter table public.budget_members
add column if not exists budget_id uuid references public.budgets(id) on delete cascade;

alter table public.budget_transactions
add column if not exists budget_id uuid references public.budgets(id) on delete cascade;

alter table public.budget_settlements
add column if not exists budget_id uuid references public.budgets(id) on delete cascade;

alter table public.budget_settings
add column if not exists budget_id uuid references public.budgets(id) on delete cascade;

insert into public.budgets (id, owner_user_id, name)
select distinct user_id, user_id, 'My Budget'
from (
  select user_id from public.budget_members
  union
  select user_id from public.budget_transactions
  union
  select user_id from public.budget_settlements
  union
  select user_id from public.budget_settings
) existing_users
on conflict (id) do nothing;

insert into public.budget_memberships (budget_id, user_id, role, status)
select id, owner_user_id, 'owner', 'active'
from public.budgets
on conflict (budget_id, user_id) do nothing;

update public.budget_members
set budget_id = user_id
where budget_id is null;

update public.budget_transactions
set budget_id = user_id
where budget_id is null;

update public.budget_settlements
set budget_id = user_id
where budget_id is null;

update public.budget_settings
set budget_id = user_id
where budget_id is null;

alter table public.budgets enable row level security;
alter table public.budget_memberships enable row level security;

drop policy if exists "Users can read their budgets" on public.budgets;
create policy "Users can read their budgets"
on public.budgets
for select
to authenticated
using (
  owner_user_id = auth.uid()
  or exists (
    select 1
    from public.budget_memberships membership
    where membership.budget_id = budgets.id
      and membership.user_id = auth.uid()
      and membership.status = 'active'
  )
);

drop policy if exists "Users can insert their budgets" on public.budgets;
create policy "Users can insert their budgets"
on public.budgets
for insert
to authenticated
with check (owner_user_id = auth.uid());

drop policy if exists "Users can update their budgets" on public.budgets;
create policy "Users can update their budgets"
on public.budgets
for update
to authenticated
using (owner_user_id = auth.uid())
with check (owner_user_id = auth.uid());

drop policy if exists "Users can read their budget memberships" on public.budget_memberships;
create policy "Users can read their budget memberships"
on public.budget_memberships
for select
to authenticated
using (
  user_id = auth.uid()
  or exists (
    select 1
    from public.budgets budget
    where budget.id = budget_memberships.budget_id
      and budget.owner_user_id = auth.uid()
  )
);

drop policy if exists "Users can insert their budget memberships" on public.budget_memberships;
create policy "Users can insert their budget memberships"
on public.budget_memberships
for insert
to authenticated
with check (
  user_id = auth.uid()
  or exists (
    select 1
    from public.budgets budget
    where budget.id = budget_memberships.budget_id
      and budget.owner_user_id = auth.uid()
  )
);

drop policy if exists "Users can update their budget memberships" on public.budget_memberships;
create policy "Users can update their budget memberships"
on public.budget_memberships
for update
to authenticated
using (
  user_id = auth.uid()
  or exists (
    select 1
    from public.budgets budget
    where budget.id = budget_memberships.budget_id
      and budget.owner_user_id = auth.uid()
  )
)
with check (
  user_id = auth.uid()
  or exists (
    select 1
    from public.budgets budget
    where budget.id = budget_memberships.budget_id
      and budget.owner_user_id = auth.uid()
  )
);

-- Migration: fix household RLS recursion.
drop policy if exists "Users can read their budgets" on public.budgets;
create policy "Users can read their budgets"
on public.budgets
for select
to authenticated
using (owner_user_id = auth.uid());

drop policy if exists "Users can read their budget memberships" on public.budget_memberships;
create policy "Users can read their budget memberships"
on public.budget_memberships
for select
to authenticated
using (user_id = auth.uid());

drop policy if exists "Users can insert their budget memberships" on public.budget_memberships;
create policy "Users can insert their budget memberships"
on public.budget_memberships
for insert
to authenticated
with check (user_id = auth.uid());

drop policy if exists "Users can update their budget memberships" on public.budget_memberships;
create policy "Users can update their budget memberships"
on public.budget_memberships
for update
to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

drop policy if exists "Users can delete their budget memberships" on public.budget_memberships;
create policy "Users can delete their budget memberships"
on public.budget_memberships
for delete
to authenticated
using (user_id = auth.uid() and role <> 'owner');

-- Migration: pending shared-budget invites.
create table if not exists public.budget_invites (
  id uuid primary key,
  budget_id uuid not null references public.budgets(id) on delete cascade,
  invited_by_user_id uuid not null references auth.users(id) on delete cascade,
  display_name text not null,
  email text not null,
  status text not null default 'pending' check (status in ('pending', 'accepted', 'declined', 'cancelled')),
  created_at timestamptz not null default now(),
  accepted_at timestamptz,
  unique (budget_id, email)
);

alter table public.budget_invites enable row level security;

drop policy if exists "Owners can read their budget invites" on public.budget_invites;
create policy "Owners can read their budget invites"
on public.budget_invites
for select
to authenticated
using (invited_by_user_id = auth.uid());

drop policy if exists "Owners can create budget invites" on public.budget_invites;
create policy "Owners can create budget invites"
on public.budget_invites
for insert
to authenticated
with check (invited_by_user_id = auth.uid());

drop policy if exists "Owners can update their budget invites" on public.budget_invites;
create policy "Owners can update their budget invites"
on public.budget_invites
for update
to authenticated
using (invited_by_user_id = auth.uid())
with check (invited_by_user_id = auth.uid());

-- Migration: allow invitees to view and accept their own pending invites.
drop policy if exists "Owners and invitees can read budget invites" on public.budget_invites;
create policy "Owners and invitees can read budget invites"
on public.budget_invites
for select
to authenticated
using (
  invited_by_user_id = auth.uid()
  or lower(email) = lower(coalesce(auth.jwt() ->> 'email', ''))
);

drop policy if exists "Owners and invitees can update budget invites" on public.budget_invites;
create policy "Owners and invitees can update budget invites"
on public.budget_invites
for update
to authenticated
using (
  invited_by_user_id = auth.uid()
  or (
    status = 'pending'
    and lower(email) = lower(coalesce(auth.jwt() ->> 'email', ''))
  )
)
with check (
  invited_by_user_id = auth.uid()
  or lower(email) = lower(coalesce(auth.jwt() ->> 'email', ''))
);

-- Migration: allow active budget members to read shared budget data.
drop policy if exists "Budget members can read shared members" on public.budget_members;
create policy "Budget members can read shared members"
on public.budget_members
for select
to authenticated
using (
  exists (
    select 1
    from public.budget_memberships membership
    where membership.budget_id = budget_members.budget_id
      and membership.user_id = auth.uid()
      and membership.status = 'active'
  )
);

drop policy if exists "Budget members can read shared settings" on public.budget_settings;
create policy "Budget members can read shared settings"
on public.budget_settings
for select
to authenticated
using (
  exists (
    select 1
    from public.budget_memberships membership
    where membership.budget_id = budget_settings.budget_id
      and membership.user_id = auth.uid()
      and membership.status = 'active'
  )
);

drop policy if exists "Budget members can read shared transactions" on public.budget_transactions;
create policy "Budget members can read shared transactions"
on public.budget_transactions
for select
to authenticated
using (
  exists (
    select 1
    from public.budget_memberships membership
    where membership.budget_id = budget_transactions.budget_id
      and membership.user_id = auth.uid()
      and membership.status = 'active'
  )
);

drop policy if exists "Budget members can create shared transactions" on public.budget_transactions;
create policy "Budget members can create shared transactions"
on public.budget_transactions
for insert
to authenticated
with check (
  user_id = auth.uid()
  and exists (
    select 1
    from public.budget_memberships membership
    where membership.budget_id = budget_transactions.budget_id
      and membership.user_id = auth.uid()
      and membership.status = 'active'
  )
);

drop policy if exists "Budget members can update own shared transactions" on public.budget_transactions;
create policy "Budget members can update own shared transactions"
on public.budget_transactions
for update
to authenticated
using (
  user_id = auth.uid()
  and exists (
    select 1
    from public.budget_memberships membership
    where membership.budget_id = budget_transactions.budget_id
      and membership.user_id = auth.uid()
      and membership.status = 'active'
  )
)
with check (
  user_id = auth.uid()
  and exists (
    select 1
    from public.budget_memberships membership
    where membership.budget_id = budget_transactions.budget_id
      and membership.user_id = auth.uid()
      and membership.status = 'active'
  )
);

drop policy if exists "Budget members can delete own shared transactions" on public.budget_transactions;
create policy "Budget members can delete own shared transactions"
on public.budget_transactions
for delete
to authenticated
using (
  user_id = auth.uid()
  and exists (
    select 1
    from public.budget_memberships membership
    where membership.budget_id = budget_transactions.budget_id
      and membership.user_id = auth.uid()
      and membership.status = 'active'
  )
);

drop policy if exists "Budget members can read shared settlements" on public.budget_settlements;
create policy "Budget members can read shared settlements"
on public.budget_settlements
for select
to authenticated
using (
  exists (
    select 1
    from public.budget_memberships membership
    where membership.budget_id = budget_settlements.budget_id
      and membership.user_id = auth.uid()
      and membership.status = 'active'
  )
);

drop policy if exists "Budget members can create shared settlements" on public.budget_settlements;
create policy "Budget members can create shared settlements"
on public.budget_settlements
for insert
to authenticated
with check (
  user_id = auth.uid()
  and exists (
    select 1
    from public.budget_memberships membership
    where membership.budget_id = budget_settlements.budget_id
      and membership.user_id = auth.uid()
      and membership.status = 'active'
  )
);
