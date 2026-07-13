create table if not exists public.budget_members (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  display_name text not null,
  email text,
  auth_user_id uuid references auth.users(id) on delete set null,
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
  category_emojis jsonb not null default '{}'::jsonb,
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

-- Migration: harden shared-budget membership access and support real revocation.
--
-- Important: budget_members.id is the app's profile/member id. It is not always
-- the same as auth.users.id for invited members, so auth_user_id stores the real
-- login user id once an invite is accepted.
alter table public.budget_members
add column if not exists auth_user_id uuid references auth.users(id) on delete set null;

alter table public.budget_invites
add column if not exists accepted_by_user_id uuid references auth.users(id) on delete set null;

update public.budget_members
set auth_user_id = user_id
where auth_user_id is null
  and id = user_id;

drop policy if exists "Users can insert their budget memberships" on public.budget_memberships;
create policy "Users can insert their budget memberships"
on public.budget_memberships
for insert
to authenticated
with check (
  user_id = auth.uid()
  and (
    exists (
      select 1
      from public.budgets budget
      where budget.id = budget_memberships.budget_id
        and budget.owner_user_id = auth.uid()
        and budget_memberships.role = 'owner'
        and budget_memberships.status = 'active'
    )
    or (
      budget_memberships.role = 'member'
      and budget_memberships.status = 'active'
      and exists (
        select 1
        from public.budget_invites invite
        where invite.budget_id = budget_memberships.budget_id
          and invite.status = 'pending'
          and lower(invite.email) = lower(coalesce(auth.jwt() ->> 'email', ''))
      )
    )
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
  exists (
    select 1
    from public.budgets budget
    where budget.id = budget_memberships.budget_id
      and budget.owner_user_id = auth.uid()
  )
  or (
    user_id = auth.uid()
    and role <> 'owner'
    and exists (
      select 1
      from public.budget_invites invite
      where invite.budget_id = budget_memberships.budget_id
        and invite.status in ('pending', 'accepted')
        and lower(invite.email) = lower(coalesce(auth.jwt() ->> 'email', ''))
    )
  )
);

drop policy if exists "Owners can remove members" on public.budget_memberships;
create policy "Owners can remove members"
on public.budget_memberships
for delete
to authenticated
using (
  user_id <> auth.uid()
  and exists (
    select 1
    from public.budgets budget
    where budget.id = budget_memberships.budget_id
      and budget.owner_user_id = auth.uid()
  )
);

drop policy if exists "Invitees can activate their budget member profile" on public.budget_members;
create policy "Invitees can activate their budget member profile"
on public.budget_members
for update
to authenticated
using (
  exists (
    select 1
    from public.budget_invites invite
    where invite.budget_id = budget_members.budget_id
      and invite.status in ('pending', 'accepted')
      and lower(invite.email) = lower(coalesce(auth.jwt() ->> 'email', ''))
      and lower(invite.email) = lower(coalesce(budget_members.email, ''))
  )
)
with check (
  auth_user_id = auth.uid()
  and invite_status = 'active'
  and exists (
    select 1
    from public.budget_invites invite
    where invite.budget_id = budget_members.budget_id
      and invite.status in ('pending', 'accepted')
      and lower(invite.email) = lower(coalesce(auth.jwt() ->> 'email', ''))
      and lower(invite.email) = lower(coalesce(budget_members.email, ''))
  )
);

-- Backfill legacy invited member rows that were accepted before auth_user_id
-- existed. Without this, older shared members can still appear as "Invited"
-- and device-to-device sync may drift until each row is linked to auth.users.
update public.budget_members member
set
  auth_user_id = auth_user.id,
  invite_status = 'active',
  joined_date = coalesce(member.joined_date, now())
from auth.users auth_user
where lower(coalesce(member.email, '')) = lower(auth_user.email)
  and member.auth_user_id is null;

update public.budget_invites invite
set accepted_by_user_id = auth_user.id
from auth.users auth_user
where lower(invite.email) = lower(auth_user.email)
  and invite.status = 'accepted'
  and invite.accepted_by_user_id is null;

-- Migration: support category emoji icons and shared-budget clear-all.
alter table public.budget_settings
add column if not exists category_emojis jsonb not null default '{}'::jsonb;

drop policy if exists "Budget members can delete shared transactions" on public.budget_transactions;
create policy "Budget members can delete shared transactions"
on public.budget_transactions
for delete
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

drop policy if exists "Budget members can delete shared settlements" on public.budget_settlements;
create policy "Budget members can delete shared settlements"
on public.budget_settlements
for delete
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

-- Migration: named shared households and per-budget settings.
alter table public.budget_settings
add column if not exists owner_user_id uuid references auth.users(id) on delete set null;

update public.budget_settings
set owner_user_id = user_id
where owner_user_id is null;

update public.budget_settings
set budget_id = user_id
where budget_id is null;

with ranked_settings as (
  select
    ctid,
    row_number() over (
      partition by budget_id
      order by updated_at desc nulls last
    ) as row_number
  from public.budget_settings
)
delete from public.budget_settings
where ctid in (
  select ctid
  from ranked_settings
  where row_number > 1
);

alter table public.budget_settings
alter column budget_id set not null;

alter table public.budget_settings
drop constraint if exists budget_settings_pkey;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'budget_settings_pkey'
      and conrelid = 'public.budget_settings'::regclass
  ) then
    alter table public.budget_settings
    add constraint budget_settings_pkey primary key (budget_id);
  end if;
end $$;

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

drop policy if exists "Budget members can write shared settings" on public.budget_settings;
create policy "Budget members can write shared settings"
on public.budget_settings
for all
to authenticated
using (
  exists (
    select 1
    from public.budget_memberships membership
    where membership.budget_id = budget_settings.budget_id
      and membership.user_id = auth.uid()
      and membership.status = 'active'
  )
)
with check (
  exists (
    select 1
    from public.budget_memberships membership
    where membership.budget_id = budget_settings.budget_id
      and membership.user_id = auth.uid()
      and membership.status = 'active'
  )
);

drop policy if exists "Owners can create budget invites" on public.budget_invites;
create policy "Owners can create budget invites"
on public.budget_invites
for insert
to authenticated
with check (
  invited_by_user_id = auth.uid()
  and exists (
    select 1
    from public.budget_memberships membership
    where membership.budget_id = budget_invites.budget_id
      and membership.user_id = auth.uid()
      and membership.role = 'owner'
      and membership.status = 'active'
  )
);

-- Migration: cross-client sync contract hardening (2026-07-11).
--
-- This block is intentionally additive before it replaces the accumulated RLS
-- policies below. Existing iOS/web payloads may omit every new column. The
-- database owns updated_at and row_version; clients must never manufacture
-- either value.
begin;

alter table public.budgets
add column if not exists row_version bigint not null default 1;

alter table public.budget_memberships
add column if not exists updated_at timestamptz not null default now();

alter table public.budget_memberships
add column if not exists row_version bigint not null default 1;

alter table public.budget_invites
add column if not exists updated_at timestamptz not null default now();

alter table public.budget_invites
add column if not exists row_version bigint not null default 1;

alter table public.budget_members
add column if not exists row_version bigint not null default 1;

alter table public.budget_settings
add column if not exists row_version bigint not null default 1;

alter table public.budget_transactions
add column if not exists row_version bigint not null default 1;

alter table public.budget_settlements
add column if not exists row_version bigint not null default 1;

-- `date` is a legacy instant even though the product treats it as a floating
-- calendar day. New clients dual-write occurred_on as YYYY-MM-DD, prefer it on
-- reads, and retain `date` only as a compatibility fallback. Do not infer this
-- value automatically: old iOS local-midnight and web local-noon values cannot
-- be losslessly mapped back to the writer's intended day without their zone.
alter table public.budget_transactions
add column if not exists occurred_on date;

alter table public.budget_settlements
add column if not exists occurred_on date;

create table if not exists public.budget_sync_tombstones (
  entity_type text not null check (entity_type in ('transaction', 'settlement')),
  budget_id uuid not null references public.budgets(id) on delete cascade,
  record_id uuid not null,
  deleted_row_version bigint not null,
  deleted_at timestamptz not null default now(),
  deleted_by_user_id uuid references auth.users(id) on delete set null,
  primary key (entity_type, budget_id, record_id)
);

alter table public.budget_sync_tombstones enable row level security;

-- SECURITY DEFINER membership predicates keep policies non-recursive. They
-- expose only booleans and use a fixed search_path.
create or replace function public.is_active_budget_member(
  p_budget_id uuid,
  p_user_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select exists (
    select 1
    from public.budget_memberships membership
    where membership.budget_id = p_budget_id
      and membership.user_id = p_user_id
      and membership.status = 'active'
  );
$$;

create or replace function public.is_budget_owner(
  p_budget_id uuid,
  p_user_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select exists (
    select 1
    from public.budgets budget
    where budget.id = p_budget_id
      and budget.owner_user_id = p_user_id
  );
$$;

revoke all on function public.is_active_budget_member(uuid, uuid) from public;
revoke all on function public.is_budget_owner(uuid, uuid) from public;
grant execute on function public.is_active_budget_member(uuid, uuid) to authenticated;
grant execute on function public.is_budget_owner(uuid, uuid) to authenticated;

-- Validate the JSON split contract in the database so malformed rows cannot
-- make iOS and web compute different totals. NOT VALID preserves legacy rows
-- for an explicit audit while enforcing the rule for every new/updated row.
create or replace function public.valid_budget_transaction_splits(
  p_type text,
  p_amount numeric,
  p_splits jsonb
)
returns boolean
language plpgsql
immutable
strict
set search_path = pg_catalog
as $$
declare
  split_row jsonb;
  split_id uuid;
  member_id uuid;
  split_amount numeric;
  split_ids uuid[] := array[]::uuid[];
  member_ids uuid[] := array[]::uuid[];
  split_total numeric := 0;
  split_count integer := 0;
begin
  if jsonb_typeof(p_splits) <> 'array' then
    return false;
  end if;

  for split_row in select value from jsonb_array_elements(p_splits)
  loop
    if jsonb_typeof(split_row) <> 'object'
       or jsonb_typeof(split_row -> 'id') <> 'string'
       or jsonb_typeof(split_row -> 'member_id') <> 'string'
       or jsonb_typeof(split_row -> 'amount') <> 'number' then
      return false;
    end if;

    split_id := (split_row ->> 'id')::uuid;
    member_id := (split_row ->> 'member_id')::uuid;
    split_amount := (split_row ->> 'amount')::numeric;

    if split_amount <= 0 or split_amount <> round(split_amount, 2) then
      return false;
    end if;

    if split_id = any(split_ids) or member_id = any(member_ids) then
      return false;
    end if;

    split_ids := array_append(split_ids, split_id);
    member_ids := array_append(member_ids, member_id);
    split_total := split_total + split_amount;
    split_count := split_count + 1;
  end loop;

  if p_type <> 'expense' and split_count > 0 then
    return false;
  end if;

  return split_count = 0 or abs(split_total - p_amount) < 0.01;
exception
  when invalid_text_representation or numeric_value_out_of_range then
    return false;
end;
$$;

revoke all on function public.valid_budget_transaction_splits(text, numeric, jsonb) from public;
grant execute on function public.valid_budget_transaction_splits(text, numeric, jsonb) to authenticated;

alter table public.budget_transactions
drop constraint if exists budget_transactions_positive_cent_amount;

alter table public.budget_transactions
add constraint budget_transactions_positive_cent_amount
check (amount > 0 and amount = round(amount, 2)) not valid;

alter table public.budget_transactions
drop constraint if exists budget_transactions_valid_splits;

alter table public.budget_transactions
add constraint budget_transactions_valid_splits
check (public.valid_budget_transaction_splits(type, amount, splits)) not valid;

alter table public.budget_settlements
drop constraint if exists budget_settlements_cent_amount;

alter table public.budget_settlements
add constraint budget_settlements_cent_amount
check (amount = round(amount, 2)) not valid;

alter table public.budget_settlements
drop constraint if exists budget_settlements_distinct_members;

alter table public.budget_settlements
add constraint budget_settlements_distinct_members
check (from_member_id <> to_member_id) not valid;

alter table public.budget_invites
drop constraint if exists budget_invites_normalized_email;

alter table public.budget_invites
add constraint budget_invites_normalized_email
check (email = lower(btrim(email)) and email <> '') not valid;

-- Budget-scoped reads, RLS predicates, and future incremental/tombstone pulls.
create index if not exists budget_members_budget_idx
on public.budget_members (budget_id, id);

create index if not exists budget_members_auth_user_idx
on public.budget_members (budget_id, auth_user_id)
where auth_user_id is not null;

create index if not exists budget_members_email_idx
on public.budget_members (budget_id, lower(email))
where email is not null;

create index if not exists budget_transactions_budget_date_idx
on public.budget_transactions (budget_id, date desc, id);

create index if not exists budget_transactions_budget_updated_idx
on public.budget_transactions (budget_id, updated_at, id);

create index if not exists budget_settlements_budget_date_idx
on public.budget_settlements (budget_id, date desc, id);

create index if not exists budget_settlements_budget_updated_idx
on public.budget_settlements (budget_id, updated_at, id);

create index if not exists budget_memberships_user_status_idx
on public.budget_memberships (user_id, status, budget_id);

create index if not exists budget_invites_email_status_idx
on public.budget_invites (lower(email), status, budget_id);

create index if not exists budget_invites_budget_status_idx
on public.budget_invites (budget_id, status, created_at desc);

create index if not exists budget_sync_tombstones_budget_deleted_idx
on public.budget_sync_tombstones (budget_id, deleted_at, record_id);

-- Server timestamps/versions are authoritative. `clock_timestamp()` is useful
-- for diagnostics and Realtime invalidation, but must not be used as a strict
-- incremental watermark because transaction commit order can differ.
create or replace function public.touch_budgetmate_sync_row()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  new.updated_at := clock_timestamp();
  if tg_op = 'INSERT' then
    new.row_version := 1;
  else
    new.row_version := old.row_version + 1;
  end if;
  return new;
end;
$$;

create or replace function public.protect_budget_identity()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  new.id := old.id;
  new.owner_user_id := old.owner_user_id;
  new.created_at := old.created_at;
  return new;
end;
$$;

create or replace function public.protect_membership_identity()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
begin
  new.budget_id := old.budget_id;
  new.user_id := old.user_id;
  new.created_at := old.created_at;

  -- Every budget must retain its canonical owner membership.
  if public.is_budget_owner(old.budget_id, old.user_id) then
    new.role := 'owner';
    new.status := 'active';
  end if;
  return new;
end;
$$;

create or replace function public.protect_settings_identity()
returns trigger
language plpgsql
set search_path = pg_catalog, public, auth
as $$
declare
  canonical_owner uuid;
begin
  select budget.owner_user_id
  into canonical_owner
  from public.budgets budget
  where budget.id = new.budget_id;

  if tg_op = 'INSERT' then
    if auth.uid() is not null then
      new.user_id := auth.uid();
    end if;
    new.owner_user_id := canonical_owner;
  else
    new.budget_id := old.budget_id;
    new.user_id := old.user_id;
    new.owner_user_id := coalesce(old.owner_user_id, canonical_owner);
  end if;
  return new;
end;
$$;

create or replace function public.protect_member_identity()
returns trigger
language plpgsql
set search_path = pg_catalog, public, auth
as $$
declare
  caller_id uuid := auth.uid();
begin
  new.id := old.id;
  new.user_id := old.user_id;
  new.budget_id := old.budget_id;
  new.created_date := old.created_date;

  -- `budget_members.role` is display data; membership is authoritative. Still,
  -- a non-owner cannot make their profile appear to be the household owner.
  if caller_id is not null
     and not public.is_budget_owner(old.budget_id, caller_id) then
    new.role := old.role;
  end if;
  return new;
end;
$$;

create or replace function public.protect_transaction_identity()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  new.id := old.id;
  new.user_id := old.user_id;
  new.budget_id := old.budget_id;
  new.created_at := old.created_at;
  return new;
end;
$$;

create or replace function public.protect_settlement_identity()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  new.id := old.id;
  new.user_id := old.user_id;
  new.budget_id := old.budget_id;
  return new;
end;
$$;

create or replace function public.protect_invite_update()
returns trigger
language plpgsql
set search_path = pg_catalog, public, auth
as $$
declare
  caller_id uuid := auth.uid();
begin
  new.id := old.id;
  new.budget_id := old.budget_id;
  new.invited_by_user_id := old.invited_by_user_id;
  new.email := old.email;
  new.created_at := old.created_at;

  -- Server-side membership/profile cleanup cancels invites in a nested trigger
  -- so removed members cannot replay them. The outer DELETE policy has already
  -- authorized that operation.
  if pg_trigger_depth() > 1 then
    return new;
  end if;

  if caller_id is not null
     and not public.is_budget_owner(old.budget_id, caller_id) then
    new.display_name := old.display_name;
    if old.status <> 'pending'
       or new.status not in ('accepted', 'declined') then
      raise exception using
        errcode = '42501',
        message = 'Invitees may only accept or decline a pending invite.';
    end if;

    if new.status = 'accepted' then
      new.accepted_by_user_id := caller_id;
      new.accepted_at := clock_timestamp();
    else
      new.accepted_by_user_id := null;
      new.accepted_at := null;
    end if;
  end if;
  return new;
end;
$$;

create or replace function public.clear_budget_data_tombstone()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  entity_name text;
begin
  entity_name := case tg_table_name
    when 'budget_transactions' then 'transaction'
    when 'budget_settlements' then 'settlement'
    else null
  end;

  if entity_name is not null then
    delete from public.budget_sync_tombstones tombstone
    where tombstone.entity_type = entity_name
      and tombstone.budget_id = new.budget_id
      and tombstone.record_id = new.id;
  end if;
  return new;
end;
$$;

create or replace function public.capture_budget_data_tombstone()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $$
declare
  entity_name text;
begin
  entity_name := case tg_table_name
    when 'budget_transactions' then 'transaction'
    when 'budget_settlements' then 'settlement'
    else null
  end;

  if entity_name is null then
    raise exception 'Unsupported tombstone table: %', tg_table_name;
  end if;

  -- A parent-budget cascade reaches this child AFTER DELETE trigger after the
  -- budget row is already gone. Do not reinsert a child tombstone and violate
  -- its budget foreign key; the entire household is being removed anyway.
  if not exists (
    select 1
    from public.budgets budget
    where budget.id = old.budget_id
  ) then
    return old;
  end if;

  insert into public.budget_sync_tombstones (
    entity_type,
    budget_id,
    record_id,
    deleted_row_version,
    deleted_at,
    deleted_by_user_id
  )
  values (
    entity_name,
    old.budget_id,
    old.id,
    old.row_version + 1,
    clock_timestamp(),
    auth.uid()
  )
  on conflict (entity_type, budget_id, record_id)
  do update set
    deleted_row_version = greatest(
      public.budget_sync_tombstones.deleted_row_version,
      excluded.deleted_row_version
    ),
    deleted_at = excluded.deleted_at,
    deleted_by_user_id = excluded.deleted_by_user_id;

  return old;
end;
$$;

revoke all on function public.touch_budgetmate_sync_row() from public;
revoke all on function public.protect_budget_identity() from public;
revoke all on function public.protect_membership_identity() from public;
revoke all on function public.protect_settings_identity() from public;
revoke all on function public.protect_member_identity() from public;
revoke all on function public.protect_transaction_identity() from public;
revoke all on function public.protect_settlement_identity() from public;
revoke all on function public.protect_invite_update() from public;
revoke all on function public.capture_budget_data_tombstone() from public;
revoke all on function public.clear_budget_data_tombstone() from public;

drop trigger if exists a_protect_budget_identity on public.budgets;
create trigger a_protect_budget_identity
before update on public.budgets
for each row execute function public.protect_budget_identity();

drop trigger if exists a_protect_membership_identity on public.budget_memberships;
create trigger a_protect_membership_identity
before update on public.budget_memberships
for each row execute function public.protect_membership_identity();

drop trigger if exists a_protect_settings_identity on public.budget_settings;
create trigger a_protect_settings_identity
before insert or update on public.budget_settings
for each row execute function public.protect_settings_identity();

drop trigger if exists a_protect_member_identity on public.budget_members;
create trigger a_protect_member_identity
before update on public.budget_members
for each row execute function public.protect_member_identity();

drop trigger if exists a_protect_transaction_identity on public.budget_transactions;
create trigger a_protect_transaction_identity
before update on public.budget_transactions
for each row execute function public.protect_transaction_identity();

drop trigger if exists a_protect_settlement_identity on public.budget_settlements;
create trigger a_protect_settlement_identity
before update on public.budget_settlements
for each row execute function public.protect_settlement_identity();

drop trigger if exists a_protect_invite_update on public.budget_invites;
create trigger a_protect_invite_update
before update on public.budget_invites
for each row execute function public.protect_invite_update();

drop trigger if exists z_touch_budgets on public.budgets;
create trigger z_touch_budgets
before insert or update on public.budgets
for each row execute function public.touch_budgetmate_sync_row();

drop trigger if exists z_touch_budget_memberships on public.budget_memberships;
create trigger z_touch_budget_memberships
before insert or update on public.budget_memberships
for each row execute function public.touch_budgetmate_sync_row();

drop trigger if exists z_touch_budget_invites on public.budget_invites;
create trigger z_touch_budget_invites
before insert or update on public.budget_invites
for each row execute function public.touch_budgetmate_sync_row();

drop trigger if exists z_touch_budget_members on public.budget_members;
create trigger z_touch_budget_members
before insert or update on public.budget_members
for each row execute function public.touch_budgetmate_sync_row();

drop trigger if exists z_touch_budget_settings on public.budget_settings;
create trigger z_touch_budget_settings
before insert or update on public.budget_settings
for each row execute function public.touch_budgetmate_sync_row();

drop trigger if exists z_touch_budget_transactions on public.budget_transactions;
create trigger z_touch_budget_transactions
before insert or update on public.budget_transactions
for each row execute function public.touch_budgetmate_sync_row();

drop trigger if exists z_touch_budget_settlements on public.budget_settlements;
create trigger z_touch_budget_settlements
before insert or update on public.budget_settlements
for each row execute function public.touch_budgetmate_sync_row();

drop trigger if exists z_capture_budget_transaction_delete on public.budget_transactions;
create trigger z_capture_budget_transaction_delete
after delete on public.budget_transactions
for each row execute function public.capture_budget_data_tombstone();

drop trigger if exists z_capture_budget_settlement_delete on public.budget_settlements;
create trigger z_capture_budget_settlement_delete
after delete on public.budget_settlements
for each row execute function public.capture_budget_data_tombstone();

drop trigger if exists z_clear_budget_transaction_tombstone on public.budget_transactions;
create trigger z_clear_budget_transaction_tombstone
after insert or update on public.budget_transactions
for each row execute function public.clear_budget_data_tombstone();

drop trigger if exists z_clear_budget_settlement_tombstone on public.budget_settlements;
create trigger z_clear_budget_settlement_tombstone
after insert or update on public.budget_settlements
for each row execute function public.clear_budget_data_tombstone();

-- Replace every historical permissive policy. PostgreSQL ORs permissive RLS
-- policies, so merely adding a stricter household policy does not override an
-- older account-scoped one.
drop policy if exists "Users can read their budgets" on public.budgets;
drop policy if exists "Users can insert their budgets" on public.budgets;
drop policy if exists "Users can update their budgets" on public.budgets;

drop policy if exists "Users can read their budget memberships" on public.budget_memberships;
drop policy if exists "Users can insert their budget memberships" on public.budget_memberships;
drop policy if exists "Users can update their budget memberships" on public.budget_memberships;
drop policy if exists "Users can delete their budget memberships" on public.budget_memberships;
drop policy if exists "Owners can remove members" on public.budget_memberships;

drop policy if exists "Owners can read their budget invites" on public.budget_invites;
drop policy if exists "Owners can create budget invites" on public.budget_invites;
drop policy if exists "Owners can update their budget invites" on public.budget_invites;
drop policy if exists "Owners and invitees can read budget invites" on public.budget_invites;
drop policy if exists "Owners and invitees can update budget invites" on public.budget_invites;

drop policy if exists "Users can read their budget members" on public.budget_members;
drop policy if exists "Users can insert their budget members" on public.budget_members;
drop policy if exists "Users can update their budget members" on public.budget_members;
drop policy if exists "Users can delete their budget members" on public.budget_members;
drop policy if exists "Budget members can read shared members" on public.budget_members;
drop policy if exists "Invitees can activate their budget member profile" on public.budget_members;

drop policy if exists "Users can read their budget settings" on public.budget_settings;
drop policy if exists "Users can insert their budget settings" on public.budget_settings;
drop policy if exists "Users can update their budget settings" on public.budget_settings;
drop policy if exists "Users can delete their budget settings" on public.budget_settings;
drop policy if exists "Budget members can read shared settings" on public.budget_settings;
drop policy if exists "Budget members can write shared settings" on public.budget_settings;

drop policy if exists "Users can read their budget transactions" on public.budget_transactions;
drop policy if exists "Users can insert their budget transactions" on public.budget_transactions;
drop policy if exists "Users can update their budget transactions" on public.budget_transactions;
drop policy if exists "Users can delete their budget transactions" on public.budget_transactions;
drop policy if exists "Budget members can read shared transactions" on public.budget_transactions;
drop policy if exists "Budget members can create shared transactions" on public.budget_transactions;
drop policy if exists "Budget members can update own shared transactions" on public.budget_transactions;
drop policy if exists "Budget members can delete own shared transactions" on public.budget_transactions;
drop policy if exists "Budget members can delete shared transactions" on public.budget_transactions;

drop policy if exists "Users can read their budget settlements" on public.budget_settlements;
drop policy if exists "Users can insert their budget settlements" on public.budget_settlements;
drop policy if exists "Users can update their budget settlements" on public.budget_settlements;
drop policy if exists "Users can delete their budget settlements" on public.budget_settlements;
drop policy if exists "Budget members can read shared settlements" on public.budget_settlements;
drop policy if exists "Budget members can create shared settlements" on public.budget_settlements;
drop policy if exists "Budget members can delete shared settlements" on public.budget_settlements;

-- Make this final policy set safe to rerun as part of the full schema file.
drop policy if exists "Active members can read budgets" on public.budgets;
drop policy if exists "Users can create owned budgets" on public.budgets;
drop policy if exists "Owners can update budgets" on public.budgets;

drop policy if exists "Members can read household memberships" on public.budget_memberships;
drop policy if exists "Users can create valid memberships" on public.budget_memberships;
drop policy if exists "Owners and invited users can update memberships" on public.budget_memberships;
drop policy if exists "Members can leave and owners can remove members" on public.budget_memberships;

drop policy if exists "Owners and invitees can read invites" on public.budget_invites;
drop policy if exists "Owners can create normalized invites" on public.budget_invites;
drop policy if exists "Owners and invitees can update invites" on public.budget_invites;
drop policy if exists "Owners can delete invites" on public.budget_invites;

drop policy if exists "Active members can read member profiles" on public.budget_members;
drop policy if exists "Owners and active users can create member profiles" on public.budget_members;
drop policy if exists "Owners users and invitees can update member profiles" on public.budget_members;
drop policy if exists "Owners and users can delete member profiles" on public.budget_members;

drop policy if exists "Active members can read settings" on public.budget_settings;
drop policy if exists "Active members can create settings" on public.budget_settings;
drop policy if exists "Active members can update settings" on public.budget_settings;
drop policy if exists "Active members can delete settings" on public.budget_settings;

drop policy if exists "Active members can read transactions" on public.budget_transactions;
drop policy if exists "Active members can create owned transactions" on public.budget_transactions;
drop policy if exists "Creators and owners can update transactions" on public.budget_transactions;
drop policy if exists "Active members can delete transactions" on public.budget_transactions;

drop policy if exists "Active members can read settlements" on public.budget_settlements;
drop policy if exists "Active members can create owned settlements" on public.budget_settlements;
drop policy if exists "Creators and owners can update settlements" on public.budget_settlements;
drop policy if exists "Active members can delete settlements" on public.budget_settlements;

create policy "Active members can read budgets"
on public.budgets
for select
to authenticated
using (
  owner_user_id = (select auth.uid())
  or public.is_active_budget_member(id, (select auth.uid()))
);

create policy "Users can create owned budgets"
on public.budgets
for insert
to authenticated
with check (owner_user_id = (select auth.uid()));

create policy "Owners can update budgets"
on public.budgets
for update
to authenticated
using (owner_user_id = (select auth.uid()))
with check (owner_user_id = (select auth.uid()));

create policy "Members can read household memberships"
on public.budget_memberships
for select
to authenticated
using (
  user_id = (select auth.uid())
  or public.is_active_budget_member(budget_id, (select auth.uid()))
  or public.is_budget_owner(budget_id, (select auth.uid()))
);

create policy "Users can create valid memberships"
on public.budget_memberships
for insert
to authenticated
with check (
  user_id = (select auth.uid())
  and (
    (
      role = 'owner'
      and status = 'active'
      and public.is_budget_owner(budget_id, (select auth.uid()))
    )
    or (
      role = 'member'
      and status = 'active'
      and exists (
        select 1
        from public.budget_invites invite
        where invite.budget_id = budget_memberships.budget_id
          and invite.status = 'pending'
          and lower(invite.email) = lower(coalesce(auth.jwt() ->> 'email', ''))
      )
    )
  )
);

create policy "Owners and invited users can update memberships"
on public.budget_memberships
for update
to authenticated
using (
  public.is_budget_owner(budget_id, (select auth.uid()))
  or (user_id = (select auth.uid()) and role <> 'owner')
)
with check (
  public.is_budget_owner(budget_id, (select auth.uid()))
  or (
    user_id = (select auth.uid())
    and role = 'member'
    and status = 'active'
    and exists (
      select 1
      from public.budget_invites invite
      where invite.budget_id = budget_memberships.budget_id
        and invite.status in ('pending', 'accepted')
        and lower(invite.email) = lower(coalesce(auth.jwt() ->> 'email', ''))
    )
  )
);

create policy "Members can leave and owners can remove members"
on public.budget_memberships
for delete
to authenticated
using (
  (user_id = (select auth.uid()) and role <> 'owner')
  or (
    user_id <> (select auth.uid())
    and public.is_budget_owner(budget_id, (select auth.uid()))
  )
);

create policy "Owners and invitees can read invites"
on public.budget_invites
for select
to authenticated
using (
  public.is_budget_owner(budget_id, (select auth.uid()))
  or lower(email) = lower(coalesce(auth.jwt() ->> 'email', ''))
);

create policy "Owners can create normalized invites"
on public.budget_invites
for insert
to authenticated
with check (
  invited_by_user_id = (select auth.uid())
  and public.is_budget_owner(budget_id, (select auth.uid()))
  and email = lower(btrim(email))
  and email <> ''
);

create policy "Owners and invitees can update invites"
on public.budget_invites
for update
to authenticated
using (
  public.is_budget_owner(budget_id, (select auth.uid()))
  or (
    status = 'pending'
    and lower(email) = lower(coalesce(auth.jwt() ->> 'email', ''))
  )
)
with check (
  public.is_budget_owner(budget_id, (select auth.uid()))
  or lower(email) = lower(coalesce(auth.jwt() ->> 'email', ''))
);

create policy "Owners can delete invites"
on public.budget_invites
for delete
to authenticated
using (public.is_budget_owner(budget_id, (select auth.uid())));

create policy "Active members can read member profiles"
on public.budget_members
for select
to authenticated
using (public.is_active_budget_member(budget_id, (select auth.uid())));

create policy "Owners and active users can create member profiles"
on public.budget_members
for insert
to authenticated
with check (
  (
    public.is_budget_owner(budget_id, (select auth.uid()))
    and user_id = (select auth.uid())
  )
  or (
    auth_user_id = (select auth.uid())
    and user_id = (select auth.uid())
    and public.is_active_budget_member(budget_id, (select auth.uid()))
  )
);

create policy "Owners users and invitees can update member profiles"
on public.budget_members
for update
to authenticated
using (
  public.is_budget_owner(budget_id, (select auth.uid()))
  or auth_user_id = (select auth.uid())
  or exists (
    select 1
    from public.budget_invites invite
    where invite.budget_id = budget_members.budget_id
      and invite.status in ('pending', 'accepted')
      and lower(invite.email) = lower(coalesce(auth.jwt() ->> 'email', ''))
      and lower(invite.email) = lower(coalesce(budget_members.email, ''))
  )
)
with check (
  public.is_budget_owner(budget_id, (select auth.uid()))
  or (
    auth_user_id = (select auth.uid())
    and (
      public.is_active_budget_member(budget_id, (select auth.uid()))
      or exists (
        select 1
        from public.budget_invites invite
        where invite.budget_id = budget_members.budget_id
          and invite.status in ('pending', 'accepted')
          and lower(invite.email) = lower(coalesce(auth.jwt() ->> 'email', ''))
          and lower(invite.email) = lower(coalesce(budget_members.email, ''))
      )
    )
  )
);

create policy "Owners and users can delete member profiles"
on public.budget_members
for delete
to authenticated
using (public.is_budget_owner(budget_id, (select auth.uid())));

create policy "Active members can read settings"
on public.budget_settings
for select
to authenticated
using (public.is_active_budget_member(budget_id, (select auth.uid())));

create policy "Active members can create settings"
on public.budget_settings
for insert
to authenticated
with check (public.is_active_budget_member(budget_id, (select auth.uid())));

create policy "Active members can update settings"
on public.budget_settings
for update
to authenticated
using (public.is_active_budget_member(budget_id, (select auth.uid())))
with check (public.is_active_budget_member(budget_id, (select auth.uid())));

create policy "Active members can delete settings"
on public.budget_settings
for delete
to authenticated
using (public.is_active_budget_member(budget_id, (select auth.uid())));

create policy "Active members can read transactions"
on public.budget_transactions
for select
to authenticated
using (public.is_active_budget_member(budget_id, (select auth.uid())));

create policy "Active members can create owned transactions"
on public.budget_transactions
for insert
to authenticated
with check (
  user_id = (select auth.uid())
  and public.is_active_budget_member(budget_id, (select auth.uid()))
);

create policy "Creators and owners can update transactions"
on public.budget_transactions
for update
to authenticated
using (
  public.is_active_budget_member(budget_id, (select auth.uid()))
  and (
    user_id = (select auth.uid())
    or public.is_budget_owner(budget_id, (select auth.uid()))
  )
)
with check (
  public.is_active_budget_member(budget_id, (select auth.uid()))
  and (
    user_id = (select auth.uid())
    or public.is_budget_owner(budget_id, (select auth.uid()))
  )
);

create policy "Active members can delete transactions"
on public.budget_transactions
for delete
to authenticated
using (public.is_active_budget_member(budget_id, (select auth.uid())));

create policy "Active members can read settlements"
on public.budget_settlements
for select
to authenticated
using (public.is_active_budget_member(budget_id, (select auth.uid())));

create policy "Active members can create owned settlements"
on public.budget_settlements
for insert
to authenticated
with check (
  user_id = (select auth.uid())
  and public.is_active_budget_member(budget_id, (select auth.uid()))
);

create policy "Creators and owners can update settlements"
on public.budget_settlements
for update
to authenticated
using (
  public.is_active_budget_member(budget_id, (select auth.uid()))
  and (
    user_id = (select auth.uid())
    or public.is_budget_owner(budget_id, (select auth.uid()))
  )
)
with check (
  public.is_active_budget_member(budget_id, (select auth.uid()))
  and (
    user_id = (select auth.uid())
    or public.is_budget_owner(budget_id, (select auth.uid()))
  )
);

create policy "Active members can delete settlements"
on public.budget_settlements
for delete
to authenticated
using (public.is_active_budget_member(budget_id, (select auth.uid())));

drop policy if exists "Active members can read sync tombstones" on public.budget_sync_tombstones;
create policy "Active members can read sync tombstones"
on public.budget_sync_tombstones
for select
to authenticated
using (public.is_active_budget_member(budget_id, (select auth.uid())));

-- Removing/leaving/deactivating a membership deactivates its display profile
-- and cancels the invite that authorized it. The email match also covers a
-- legacy/direct acceptance that created the membership but failed before it
-- marked the invite accepted; otherwise that pending invite could be replayed
-- immediately after revocation.
create or replace function public.deactivate_removed_budget_member()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if public.is_budget_owner(old.budget_id, old.user_id) then
    if tg_op = 'DELETE' then
      return old;
    end if;
    return new;
  end if;

  if tg_op = 'UPDATE' then
    if old.status <> 'active' or new.status = 'active' then
      return new;
    end if;
  end if;

  -- Cancel before unlinking the profile so its original invite email is still
  -- available even if the account email changed after acceptance.
  update public.budget_invites invite
  set status = 'cancelled'
  where invite.budget_id = old.budget_id
    and invite.status in ('pending', 'accepted')
    and (
      invite.accepted_by_user_id = old.user_id
      or exists (
        select 1
        from public.budget_members member
        where member.budget_id = old.budget_id
          and member.auth_user_id = old.user_id
          and lower(member.email) = lower(invite.email)
      )
      or exists (
        select 1
        from auth.users removed_user
        where removed_user.id = old.user_id
          and lower(removed_user.email) = lower(invite.email)
      )
    );

  update public.budget_members member
  set
    auth_user_id = null,
    invite_status = 'invited'
  where member.budget_id = old.budget_id
    and member.auth_user_id = old.user_id;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

revoke all on function public.deactivate_removed_budget_member() from public;

drop trigger if exists z_deactivate_removed_budget_member on public.budget_memberships;
create trigger z_deactivate_removed_budget_member
after delete or update on public.budget_memberships
for each row execute function public.deactivate_removed_budget_member();

-- Member-management clients historically deleted the display profile and the
-- authorization membership in separate requests. Make profile deletion the
-- atomic authorization boundary: cancel its invite and remove any linked
-- non-owner membership in the same transaction. A missing parent budget means
-- this is a budget-wide ON DELETE CASCADE, where no cleanup rows should survive.
create or replace function public.revoke_deleted_budget_member_access()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  canonical_owner_id uuid;
begin
  select budget.owner_user_id
  into canonical_owner_id
  from public.budgets budget
  where budget.id = old.budget_id;

  if not found then
    return old;
  end if;

  -- Never let deleting display data revoke the canonical owner's access. The
  -- id fallback covers the original personal-budget profile shape.
  if old.auth_user_id = canonical_owner_id
     or (old.auth_user_id is null and old.id = canonical_owner_id) then
    return old;
  end if;

  update public.budget_invites invite
  set status = 'cancelled'
  where invite.budget_id = old.budget_id
    and invite.status in ('pending', 'accepted')
    and (
      (
        old.auth_user_id is not null
        and invite.accepted_by_user_id = old.auth_user_id
      )
      or (
        old.email is not null
        and lower(btrim(invite.email)) = lower(btrim(old.email))
      )
    );

  if old.auth_user_id is not null then
    delete from public.budget_memberships membership
    where membership.budget_id = old.budget_id
      and membership.user_id = old.auth_user_id
      and membership.user_id <> canonical_owner_id;
  end if;

  return old;
end;
$$;

revoke all on function public.revoke_deleted_budget_member_access() from public;

drop trigger if exists z_revoke_deleted_budget_member_access on public.budget_members;
create trigger z_revoke_deleted_budget_member_access
after delete on public.budget_members
for each row execute function public.revoke_deleted_budget_member_access();

-- Atomic household bootstrap. A caller may supply stable UUIDs for retry-safe
-- client-side optimistic state, or omit them and use the returned budget id.
create or replace function public.create_budget_household(
  p_name text,
  p_budget_id uuid default null,
  p_owner_member_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $$
declare
  caller_id uuid := auth.uid();
  household_id uuid := coalesce(p_budget_id, gen_random_uuid());
  owner_member_id uuid;
  existing_owner_id uuid;
  household_name text := coalesce(nullif(btrim(p_name), ''), 'Shared Budget');
  caller_email text := nullif(lower(btrim(coalesce(auth.jwt() ->> 'email', ''))), '');
  caller_name text := coalesce(
    nullif(btrim(auth.jwt() -> 'user_metadata' ->> 'display_name'), ''),
    nullif(split_part(coalesce(auth.jwt() ->> 'email', ''), '@', 1), ''),
    'You'
  );
  now_value timestamptz := clock_timestamp();
begin
  if caller_id is null then
    raise exception using errcode = '28000', message = 'Authentication is required.';
  end if;

  select budget.owner_user_id
  into existing_owner_id
  from public.budgets budget
  where budget.id = household_id;

  if found and existing_owner_id <> caller_id then
    raise exception using errcode = '42501', message = 'That budget id belongs to another user.';
  end if;

  if not found then
    insert into public.budgets (id, owner_user_id, name, created_at, updated_at)
    values (household_id, caller_id, household_name, now_value, now_value);
  else
    update public.budgets
    set name = household_name
    where id = household_id;
  end if;

  insert into public.budget_memberships (budget_id, user_id, role, status, created_at)
  values (household_id, caller_id, 'owner', 'active', now_value)
  on conflict (budget_id, user_id)
  do update set role = 'owner', status = 'active';

  select member.id
  into owner_member_id
  from public.budget_members member
  where member.budget_id = household_id
    and (
      member.auth_user_id = caller_id
      or (caller_email is not null and lower(member.email) = caller_email)
    )
  order by (member.auth_user_id = caller_id) desc, member.created_date
  limit 1;

  if owner_member_id is null then
    owner_member_id := coalesce(p_owner_member_id, gen_random_uuid());
    if exists (
      select 1
      from public.budget_members member
      where member.id = owner_member_id
    ) then
      raise exception using errcode = '23505', message = 'That member id is already in use.';
    end if;

    insert into public.budget_members (
      id,
      user_id,
      budget_id,
      display_name,
      email,
      auth_user_id,
      initials,
      color,
      role,
      invite_status,
      joined_date,
      created_date
    )
    values (
      owner_member_id,
      caller_id,
      household_id,
      caller_name,
      caller_email,
      caller_id,
      upper(left(caller_name, 1)),
      '#3B8FE2',
      'owner',
      'active',
      now_value,
      now_value
    );
  else
    update public.budget_members
    set auth_user_id = caller_id, role = 'owner', invite_status = 'active'
    where id = owner_member_id;
  end if;

  insert into public.budget_settings (
    user_id,
    budget_id,
    owner_user_id,
    monthly_budget,
    currency_code,
    appearance,
    category_budgets,
    category_emojis
  )
  values (
    caller_id,
    household_id,
    caller_id,
    0,
    'USD',
    'system',
    '{}'::jsonb,
    '{}'::jsonb
  )
  on conflict (budget_id) do nothing;

  return household_id;
end;
$$;

-- Atomic and idempotent for the same active acceptance. It validates the JWT
-- email, locks the invite, creates membership/profile state, and marks the
-- invite accepted in one database transaction.
create or replace function public.accept_budget_invite(p_invite_id uuid)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $$
declare
  caller_id uuid := auth.uid();
  caller_email text := nullif(lower(btrim(coalesce(auth.jwt() ->> 'email', ''))), '');
  invite_row public.budget_invites%rowtype;
  matching_profile_count integer;
  now_value timestamptz := clock_timestamp();
begin
  if caller_id is null or caller_email is null then
    raise exception using errcode = '28000', message = 'An authenticated email is required.';
  end if;

  select *
  into invite_row
  from public.budget_invites invite
  where invite.id = p_invite_id
  for update;

  if not found then
    raise exception using errcode = 'P0002', message = 'Invite not found.';
  end if;

  if lower(invite_row.email) <> caller_email then
    raise exception using errcode = '42501', message = 'This invite belongs to another email.';
  end if;

  if invite_row.status = 'accepted' then
    if invite_row.accepted_by_user_id <> caller_id
       or not exists (
         select 1
         from public.budget_memberships membership
         where membership.budget_id = invite_row.budget_id
           and membership.user_id = caller_id
           and membership.status = 'active'
       ) then
      raise exception using errcode = '42501', message = 'This invite is no longer active.';
    end if;
  elsif invite_row.status <> 'pending' then
    raise exception using errcode = 'P0001', message = 'This invite is no longer pending.';
  end if;

  if exists (
    select 1
    from public.budget_members member
    where member.budget_id = invite_row.budget_id
      and lower(coalesce(member.email, '')) = caller_email
      and member.auth_user_id is not null
      and member.auth_user_id <> caller_id
  ) then
    raise exception using errcode = '23505', message = 'That member profile is linked to another account.';
  end if;

  insert into public.budget_memberships (budget_id, user_id, role, status)
  values (invite_row.budget_id, caller_id, 'member', 'active')
  on conflict (budget_id, user_id)
  do update set
    role = case
      when public.budget_memberships.role = 'owner' then 'owner'
      else 'member'
    end,
    status = 'active';

  update public.budget_members member
  set
    auth_user_id = caller_id,
    invite_status = 'active',
    joined_date = coalesce(member.joined_date, now_value)
  where member.budget_id = invite_row.budget_id
    and lower(coalesce(member.email, '')) = caller_email;

  get diagnostics matching_profile_count = row_count;
  if matching_profile_count = 0 then
    insert into public.budget_members (
      id,
      user_id,
      budget_id,
      display_name,
      email,
      auth_user_id,
      initials,
      color,
      role,
      invite_status,
      joined_date,
      created_date
    )
    values (
      gen_random_uuid(),
      invite_row.invited_by_user_id,
      invite_row.budget_id,
      invite_row.display_name,
      caller_email,
      caller_id,
      upper(left(invite_row.display_name, 1)),
      '#1FA37D',
      'member',
      'active',
      now_value,
      now_value
    );
  end if;

  if invite_row.status = 'pending' then
    update public.budget_invites
    set
      status = 'accepted',
      accepted_at = now_value,
      accepted_by_user_id = caller_id
    where id = invite_row.id;
  end if;

  return invite_row.budget_id;
end;
$$;

revoke all on function public.create_budget_household(text, uuid, uuid) from public;
revoke all on function public.accept_budget_invite(uuid) from public;
grant execute on function public.create_budget_household(text, uuid, uuid) to authenticated;
grant execute on function public.accept_budget_invite(uuid) to authenticated;

-- Publish budget changes when Supabase Realtime is present. FULL identity
-- records complete old rows in the WAL, but Supabase Postgres Changes exposes
-- only primary keys from old rows when RLS is enabled and cannot filter DELETE
-- events. Consumers must subscribe without a budget_id filter, treat every
-- event as an invalidation hint, and perform a coalesced RLS-scoped fetch.
alter table public.budgets replica identity full;
alter table public.budget_memberships replica identity full;
alter table public.budget_invites replica identity full;
alter table public.budget_members replica identity full;
alter table public.budget_settings replica identity full;
alter table public.budget_transactions replica identity full;
alter table public.budget_settlements replica identity full;
alter table public.budget_sync_tombstones replica identity full;

do $$
declare
  table_name text;
begin
  if exists (
    select 1
    from pg_catalog.pg_publication
    where pubname = 'supabase_realtime'
      and not puballtables
  ) then
    foreach table_name in array array[
      'budgets',
      'budget_memberships',
      'budget_invites',
      'budget_members',
      'budget_settings',
      'budget_transactions',
      'budget_settlements',
      'budget_sync_tombstones'
    ]
    loop
      if not exists (
        select 1
        from pg_catalog.pg_publication_tables publication_table
        where publication_table.pubname = 'supabase_realtime'
          and publication_table.schemaname = 'public'
          and publication_table.tablename = table_name
      ) then
        execute format(
          'alter publication supabase_realtime add table public.%I',
          table_name
        );
      end if;
    end loop;
  end if;
end $$;

commit;
