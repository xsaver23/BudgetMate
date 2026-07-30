\set ON_ERROR_STOP on

-- Reproduce the unledgered production drift that was present before 00300.
-- This fixture intentionally installs the old authenticated surface so the
-- pending migration must retire it, rather than merely proving a clean schema
-- can receive the new Gate C objects.

-- Supabase grants client schema access in the hosted project. Reproduce that
-- boundary in the disposable database so the disabled contract exercises RLS
-- and function ACLs rather than failing on fixture plumbing.
grant usage on schema public, auth to authenticated;
grant execute on function auth.uid() to authenticated;

alter table public.budget_transactions
  add column if not exists last_mutation_id uuid;

alter table public.budget_settlements
  add column if not exists last_mutation_id uuid;

create or replace function public.clear_reused_financial_mutation_id()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  if new.last_mutation_id is not distinct from old.last_mutation_id then
    new.last_mutation_id := null;
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

drop trigger if exists b_clear_reused_transaction_mutation_id
on public.budget_transactions;
create trigger b_clear_reused_transaction_mutation_id
before update on public.budget_transactions
for each row execute function public.clear_reused_financial_mutation_id();

drop trigger if exists b_clear_reused_settlement_mutation_id
on public.budget_settlements;
create trigger b_clear_reused_settlement_mutation_id
before update on public.budget_settlements
for each row execute function public.clear_reused_financial_mutation_id();

drop trigger if exists z_capture_budget_transaction_delete
on public.budget_transactions;
create trigger z_capture_budget_transaction_delete
after delete on public.budget_transactions
for each row execute function public.capture_budget_data_tombstone();

drop trigger if exists z_capture_budget_settlement_delete
on public.budget_settlements;
create trigger z_capture_budget_settlement_delete
after delete on public.budget_settlements
for each row execute function public.capture_budget_data_tombstone();

drop trigger if exists z_clear_budget_transaction_tombstone
on public.budget_transactions;
create trigger z_clear_budget_transaction_tombstone
after insert or update on public.budget_transactions
for each row execute function public.clear_budget_data_tombstone();

drop trigger if exists z_clear_budget_settlement_tombstone
on public.budget_settlements;
create trigger z_clear_budget_settlement_tombstone
after insert or update on public.budget_settlements
for each row execute function public.clear_budget_data_tombstone();

-- Keep the input signatures and authenticated SECURITY DEFINER grants from the
-- live drift. The fixture bodies deliberately do not write fixture data: any
-- accidental pre-migration invocation fails closed, while the migration tests
-- that the obsolete callable objects no longer exist at all.
drop function if exists public.save_budget_transaction_cas(jsonb, bigint, uuid);
create function public.save_budget_transaction_cas(
  p_payload jsonb,
  p_expected_row_version bigint,
  p_mutation_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $$
begin
  raise exception using errcode = '55000', message = 'legacy_fixture_rpc';
end;
$$;

drop function if exists public.save_budget_settlement_cas(jsonb, bigint, uuid);
create function public.save_budget_settlement_cas(
  p_payload jsonb,
  p_expected_row_version bigint,
  p_mutation_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $$
begin
  raise exception using errcode = '55000', message = 'legacy_fixture_rpc';
end;
$$;

drop function if exists public.save_budget_transactions_cas(jsonb);
create function public.save_budget_transactions_cas(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $$
begin
  raise exception using errcode = '55000', message = 'legacy_fixture_rpc';
end;
$$;

drop function if exists public.save_budget_settlements_cas(jsonb);
create function public.save_budget_settlements_cas(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $$
begin
  raise exception using errcode = '55000', message = 'legacy_fixture_rpc';
end;
$$;

drop function if exists public.delete_budget_transaction_cas(uuid, uuid, bigint);
create function public.delete_budget_transaction_cas(
  p_id uuid,
  p_budget_id uuid,
  p_expected_row_version bigint
)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $$
begin
  raise exception using errcode = '55000', message = 'legacy_fixture_rpc';
end;
$$;

drop function if exists public.delete_budget_settlement_cas(uuid, uuid, bigint);
create function public.delete_budget_settlement_cas(
  p_id uuid,
  p_budget_id uuid,
  p_expected_row_version bigint
)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $$
begin
  raise exception using errcode = '55000', message = 'legacy_fixture_rpc';
end;
$$;

revoke all on function public.save_budget_transaction_cas(jsonb, bigint, uuid)
from public, anon, authenticated;
revoke all on function public.save_budget_settlement_cas(jsonb, bigint, uuid)
from public, anon, authenticated;
revoke all on function public.save_budget_transactions_cas(jsonb)
from public, anon, authenticated;
revoke all on function public.save_budget_settlements_cas(jsonb)
from public, anon, authenticated;
revoke all on function public.delete_budget_transaction_cas(uuid, uuid, bigint)
from public, anon, authenticated;
revoke all on function public.delete_budget_settlement_cas(uuid, uuid, bigint)
from public, anon, authenticated;

grant execute on function public.save_budget_transaction_cas(jsonb, bigint, uuid)
to authenticated;
grant execute on function public.save_budget_settlement_cas(jsonb, bigint, uuid)
to authenticated;
grant execute on function public.save_budget_transactions_cas(jsonb)
to authenticated;
grant execute on function public.save_budget_settlements_cas(jsonb)
to authenticated;
grant execute on function public.delete_budget_transaction_cas(uuid, uuid, bigint)
to authenticated;
grant execute on function public.delete_budget_settlement_cas(uuid, uuid, bigint)
to authenticated;

alter table public.budget_transactions enable row level security;
alter table public.budget_settlements enable row level security;

drop policy if exists "Active members can read transactions" on public.budget_transactions;
drop policy if exists "Active members can create owned transactions" on public.budget_transactions;
drop policy if exists "Active members can update transactions" on public.budget_transactions;
drop policy if exists "Creators and owners can delete transactions" on public.budget_transactions;
create policy "Active members can read transactions"
on public.budget_transactions
for select
to authenticated
using (
  exists (
    select 1
    from public.budget_memberships membership
    where membership.budget_id = budget_transactions.budget_id
      and membership.user_id = (select auth.uid())
      and membership.status = 'active'
  )
);
create policy "Active members can create owned transactions"
on public.budget_transactions
for insert
to authenticated
with check (
  user_id = (select auth.uid())
  and exists (
    select 1
    from public.budget_memberships membership
    where membership.budget_id = budget_transactions.budget_id
      and membership.user_id = (select auth.uid())
      and membership.status = 'active'
  )
);
create policy "Active members can update transactions"
on public.budget_transactions
for update
to authenticated
using (true)
with check (true);
create policy "Creators and owners can delete transactions"
on public.budget_transactions
for delete
to authenticated
using (true);

drop policy if exists "Active members can read settlements" on public.budget_settlements;
drop policy if exists "Active members can create owned settlements" on public.budget_settlements;
drop policy if exists "Creators and owners can update settlements" on public.budget_settlements;
drop policy if exists "Creators and owners can delete settlements" on public.budget_settlements;
create policy "Active members can read settlements"
on public.budget_settlements
for select
to authenticated
using (
  exists (
    select 1
    from public.budget_memberships membership
    where membership.budget_id = budget_settlements.budget_id
      and membership.user_id = (select auth.uid())
      and membership.status = 'active'
  )
);
create policy "Active members can create owned settlements"
on public.budget_settlements
for insert
to authenticated
with check (
  user_id = (select auth.uid())
  and exists (
    select 1
    from public.budget_memberships membership
    where membership.budget_id = budget_settlements.budget_id
      and membership.user_id = (select auth.uid())
      and membership.status = 'active'
  )
);
create policy "Creators and owners can update settlements"
on public.budget_settlements
for update
to authenticated
using (true)
with check (true);
create policy "Creators and owners can delete settlements"
on public.budget_settlements
for delete
to authenticated
using (true);

do $$
begin
  if (select count(*) from (values
    (to_regprocedure('public.save_budget_transaction_cas(jsonb,bigint,uuid)')),
    (to_regprocedure('public.save_budget_settlement_cas(jsonb,bigint,uuid)')),
    (to_regprocedure('public.save_budget_transactions_cas(jsonb)')),
    (to_regprocedure('public.save_budget_settlements_cas(jsonb)')),
    (to_regprocedure('public.delete_budget_transaction_cas(uuid,uuid,bigint)')),
    (to_regprocedure('public.delete_budget_settlement_cas(uuid,uuid,bigint)'))
  ) as legacy_functions(regprocedure) where regprocedure is null) <> 0 then
    raise exception 'Legacy RPC fixture is incomplete';
  end if;

  if (select count(*)
      from pg_trigger
      where tgname in (
        'b_clear_reused_transaction_mutation_id',
        'b_clear_reused_settlement_mutation_id',
        'z_capture_budget_transaction_delete',
        'z_capture_budget_settlement_delete',
        'z_clear_budget_transaction_tombstone',
        'z_clear_budget_settlement_tombstone'
      )
        and not tgisinternal) <> 6 then
    raise exception 'Legacy trigger fixture is incomplete';
  end if;

  if (select count(*)
      from (values
        ('public.save_budget_transaction_cas(jsonb,bigint,uuid)'),
        ('public.save_budget_settlement_cas(jsonb,bigint,uuid)'),
        ('public.save_budget_transactions_cas(jsonb)'),
        ('public.save_budget_settlements_cas(jsonb)'),
        ('public.delete_budget_transaction_cas(uuid,uuid,bigint)'),
        ('public.delete_budget_settlement_cas(uuid,uuid,bigint)')
      ) as legacy_grants(signature)
      where has_function_privilege('authenticated', signature, 'EXECUTE')) <> 6 then
    raise exception 'Legacy authenticated RPC grants are missing';
  end if;

  if (select count(*)
      from pg_policies
      where schemaname = 'public'
        and tablename in ('budget_transactions', 'budget_settlements')
        and policyname in (
          'Active members can create owned transactions',
          'Active members can update transactions',
          'Creators and owners can delete transactions',
          'Active members can create owned settlements',
          'Creators and owners can update settlements',
          'Creators and owners can delete settlements'
        )) <> 6 then
    raise exception 'Legacy write-policy fixture is incomplete';
  end if;
end
$$;
