\set ON_ERROR_STOP on

drop schema if exists public cascade;
create schema public;

create schema auth;

create table auth.users (
  id uuid primary key,
  email text not null
);

insert into auth.users (id, email)
values
  ('90000000-0000-0000-0000-000000000001', 'alice@example.com'),
  ('90000000-0000-0000-0000-000000000002', 'bob@example.com'),
  ('90000000-0000-0000-0000-000000000003', 'carol@example.com');

create or replace function auth.uid()
returns uuid
language sql
stable
as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
$$;

do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    create role anon;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    create role authenticated;
  end if;
  if not exists (
    select 1 from pg_roles
    where rolname = concat('service', '_role')
  ) then
    execute format('create role %I', concat('service', '_role'));
  end if;
end
$$;

create table public.budgets (
  id uuid primary key,
  owner_user_id uuid not null,
  name text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  row_version bigint not null default 1
);

create table public.budget_settings (
  user_id uuid not null,
  monthly_budget numeric not null default 0,
  currency_code text not null,
  appearance text not null default 'system',
  category_budgets jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  budget_id uuid primary key references public.budgets(id),
  category_emojis jsonb not null default '{}'::jsonb,
  owner_user_id uuid not null,
  row_version bigint not null default 1
);

create table public.budget_memberships (
  budget_id uuid not null references public.budgets(id),
  user_id uuid not null references auth.users(id),
  role text not null,
  status text not null,
  primary key (budget_id, user_id)
);

create table public.budget_members (
  id uuid primary key,
  user_id uuid not null references auth.users(id),
  budget_id uuid not null references public.budgets(id),
  auth_user_id uuid references auth.users(id),
  invite_status text not null
);

create table public.budget_sync_tombstones (
  entity_type text not null,
  budget_id uuid not null references public.budgets(id),
  record_id uuid not null,
  deleted_row_version bigint not null,
  deleted_at timestamptz not null default now(),
  deleted_by_user_id uuid references auth.users(id) on delete set null,
  primary key (entity_type, budget_id, record_id)
);

create table public.budget_transactions (
  id uuid primary key,
  user_id uuid not null,
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
  updated_at timestamptz not null default now(),
  budget_id uuid references public.budgets(id),
  row_version bigint not null default 1,
  occurred_on date,
  last_mutation_id uuid
);

create table public.budget_settlements (
  id uuid primary key,
  user_id uuid not null,
  from_member_id uuid not null,
  to_member_id uuid not null,
  amount numeric not null check (amount > 0),
  date timestamptz not null,
  updated_at timestamptz not null default now(),
  budget_id uuid references public.budgets(id),
  row_version bigint not null default 1,
  occurred_on date,
  last_mutation_id uuid
);

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
    if split_amount <= 0
       or split_amount <> round(split_amount, 2)
       or split_id = any(split_ids)
       or member_id = any(member_ids) then
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

alter table public.budget_transactions
  add constraint budget_transactions_valid_splits
  check (public.valid_budget_transaction_splits(type, amount, splits));

insert into public.budgets (id, owner_user_id, name)
values
  ('10000000-0000-0000-0000-000000000001', '90000000-0000-0000-0000-000000000001', 'USD household'),
  ('10000000-0000-0000-0000-000000000002', '90000000-0000-0000-0000-000000000002', 'JPY household'),
  ('10000000-0000-0000-0000-000000000003', '90000000-0000-0000-0000-000000000003', 'Empty household');

insert into public.budget_settings (
  user_id,
  monthly_budget,
  currency_code,
  category_budgets,
  budget_id,
  owner_user_id
)
values
  (
    '90000000-0000-0000-0000-000000000001',
    0,
    'USD',
    '{"food":12.34,"__monthBudget__:2026-07:food":5.67,"__hiddenCategory__restaurant":1}',
    '10000000-0000-0000-0000-000000000001',
    '90000000-0000-0000-0000-000000000001'
  ),
  (
    '90000000-0000-0000-0000-000000000002',
    250,
    'JPY',
    '{}',
    '10000000-0000-0000-0000-000000000002',
    '90000000-0000-0000-0000-000000000002'
  ),
  (
    '90000000-0000-0000-0000-000000000003',
    0,
    'USD',
    '{}',
    '10000000-0000-0000-0000-000000000003',
    '90000000-0000-0000-0000-000000000003'
  );

insert into public.budget_memberships (budget_id, user_id, role, status)
values
  ('10000000-0000-0000-0000-000000000001', '90000000-0000-0000-0000-000000000001', 'owner', 'active'),
  ('10000000-0000-0000-0000-000000000002', '90000000-0000-0000-0000-000000000002', 'owner', 'active'),
  ('10000000-0000-0000-0000-000000000003', '90000000-0000-0000-0000-000000000003', 'owner', 'active');

insert into public.budget_members (id, user_id, budget_id, auth_user_id, invite_status)
values
  ('80000000-0000-0000-0000-000000000001', '90000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', '90000000-0000-0000-0000-000000000001', 'active'),
  ('80000000-0000-0000-0000-000000000002', '90000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000001', '90000000-0000-0000-0000-000000000002', 'active'),
  ('80000000-0000-0000-0000-000000000003', '90000000-0000-0000-0000-000000000003', '10000000-0000-0000-0000-000000000002', '90000000-0000-0000-0000-000000000003', 'active');

insert into public.budget_transactions (
  id,
  user_id,
  title,
  amount,
  type,
  category,
  created_by_member_id,
  date,
  created_at,
  splits,
  budget_id
)
values
  (
    '20000000-0000-0000-0000-000000000001',
    '90000000-0000-0000-0000-000000000001',
    'USD expense',
    12.34,
    'expense',
    'food',
    '80000000-0000-0000-0000-000000000001',
    now(),
    now(),
    '[{"id":"30000000-0000-0000-0000-000000000001","member_id":"80000000-0000-0000-0000-000000000001","amount":6.17},{"id":"30000000-0000-0000-0000-000000000002","member_id":"80000000-0000-0000-0000-000000000002","amount":6.17}]',
    '10000000-0000-0000-0000-000000000001'
  ),
  (
    '20000000-0000-0000-0000-000000000002',
    '90000000-0000-0000-0000-000000000002',
    'JPY expense',
    2.5,
    'expense',
    'food',
    '80000000-0000-0000-0000-000000000003',
    now(),
    now(),
    '[]',
    '10000000-0000-0000-0000-000000000002'
  );

insert into public.budget_settlements (
  id,
  user_id,
  from_member_id,
  to_member_id,
  amount,
  date,
  budget_id
)
values
  (
    '40000000-0000-0000-0000-000000000001',
    '90000000-0000-0000-0000-000000000001',
    '80000000-0000-0000-0000-000000000002',
    '80000000-0000-0000-0000-000000000001',
    25.50,
    now(),
    '10000000-0000-0000-0000-000000000001'
  );
