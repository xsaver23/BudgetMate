-- Gate C: authoritative shared-data mutation safety.
--
-- This is a forward-only migration. It deliberately starts with the server
-- gate disabled, retires the identified obsolete mutation surface, and adds
-- the Gate C contract. Once applied, transaction/settlement writes must use
-- the CAS/idempotent RPCs below; direct PostgREST writes are removed from the
-- client-facing RLS surface. Existing memberships retain read access.
-- Activation sequence: apply and rehearse this migration, upgrade all clients
-- that understand the RPC contract, verify the controlled beta, then have the
-- owner enable budget_data_safety_config.writes_enabled out of band. There is
-- no destructive down migration; rollback is restore from a pre-Gate-C dump.

begin;

do $$
begin
  if to_regclass('public.budgets') is null
     or to_regclass('public.budget_memberships') is null
     or to_regclass('public.budget_members') is null
     or to_regclass('public.budget_transactions') is null
     or to_regclass('public.budget_settlements') is null then
    raise exception 'Gate C requires budget, membership, transaction, and settlement tables';
  end if;
end
$$;

alter table public.budget_transactions
  add column if not exists created_by_user_id uuid references auth.users(id) on delete set null,
  add column if not exists last_mutation_id uuid;

alter table public.budget_settlements
  add column if not exists created_by_user_id uuid references auth.users(id) on delete set null,
  add column if not exists last_mutation_id uuid;

alter table public.budget_sync_tombstones
  add column if not exists deleted_by_mutation_id uuid;

-- A pre-00300 production drift introduced an authenticated, security-definer
-- mutation surface that does not consult budget_data_safety_config. Retire the
-- triggers first so their helper functions can be dropped without leaving an
-- alternate mutation-ID or tombstone path behind. Dropping the RPCs is stronger
-- than only revoking EXECUTE: PostgREST cannot expose an obsolete signature and
-- a stale client cannot invoke it through a cached function endpoint.
drop trigger if exists b_clear_reused_transaction_mutation_id
on public.budget_transactions;
drop trigger if exists b_clear_reused_settlement_mutation_id
on public.budget_settlements;
drop trigger if exists z_capture_budget_transaction_delete
on public.budget_transactions;
drop trigger if exists z_capture_budget_settlement_delete
on public.budget_settlements;
drop trigger if exists z_clear_budget_transaction_tombstone
on public.budget_transactions;
drop trigger if exists z_clear_budget_settlement_tombstone
on public.budget_settlements;

drop function if exists public.clear_reused_financial_mutation_id();
drop function if exists public.capture_budget_data_tombstone();
drop function if exists public.clear_budget_data_tombstone();

drop function if exists public.save_budget_transaction_cas(jsonb, bigint, uuid);
drop function if exists public.save_budget_settlement_cas(jsonb, bigint, uuid);
drop function if exists public.save_budget_transactions_cas(jsonb);
drop function if exists public.save_budget_settlements_cas(jsonb);
drop function if exists public.delete_budget_transaction_cas(uuid, uuid, bigint);
drop function if exists public.delete_budget_settlement_cas(uuid, uuid, bigint);

-- Existing user_id is the only authenticated writer identity preserved by the
-- shipped schema. Attribute that history explicitly; rows created after this
-- migration are set from auth.uid() by the RPC/trigger contract.
update public.budget_transactions
set created_by_user_id = user_id
where created_by_user_id is null;

update public.budget_settlements
set created_by_user_id = user_id
where created_by_user_id is null;

create table if not exists public.budget_data_safety_config (
  id boolean primary key default true check (id),
  writes_enabled boolean not null default false,
  updated_at timestamptz not null default now()
);

insert into public.budget_data_safety_config (id, writes_enabled)
values (true, false)
on conflict (id) do nothing;

alter table public.budget_data_safety_config enable row level security;
revoke all on table public.budget_data_safety_config from public, authenticated;

create table if not exists public.budget_mutation_receipts (
  mutation_id uuid primary key,
  budget_id uuid not null references public.budgets(id) on delete cascade,
  actor_user_id uuid not null references auth.users(id) on delete cascade,
  entity_type text not null check (entity_type in ('transaction', 'settlement')),
  record_id uuid not null,
  operation text not null check (operation in ('insert', 'update', 'delete')),
  payload_hash text not null default '',
  result_row_version bigint not null,
  result_deleted boolean not null default false,
  created_at timestamptz not null default now()
);

alter table public.budget_mutation_receipts enable row level security;
revoke all on table public.budget_mutation_receipts from public, authenticated;

-- Receipts created by an earlier Gate-C candidate had no payload binding. Keep
-- those rows replayable only with the empty legacy hash; a retry with any real
-- payload is then rejected instead of silently being treated as idempotent.
alter table public.budget_mutation_receipts
  add column if not exists payload_hash text;
update public.budget_mutation_receipts
set payload_hash = ''
where payload_hash is null;
alter table public.budget_mutation_receipts
  alter column payload_hash set default '',
  alter column payload_hash set not null;

create or replace function public.budget_data_safety_enabled()
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select coalesce(
    (select writes_enabled from public.budget_data_safety_config where id = true),
    false
  )
$$;

revoke all on function public.budget_data_safety_enabled() from public;
grant execute on function public.budget_data_safety_enabled() to authenticated;

create or replace function public.gate_c_is_active_member(
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
  )
$$;

create or replace function public.gate_c_is_owner(
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
    select 1 from public.budgets budget
    where budget.id = p_budget_id
      and budget.owner_user_id = p_user_id
  )
$$;

revoke all on function public.gate_c_is_active_member(uuid, uuid) from public;
revoke all on function public.gate_c_is_owner(uuid, uuid) from public;
grant execute on function public.gate_c_is_active_member(uuid, uuid) to authenticated;
grant execute on function public.gate_c_is_owner(uuid, uuid) to authenticated;

create or replace function public.gate_c_is_active_member_ref(
  p_budget_id uuid,
  p_member_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select exists (
    select 1
    from public.budget_members member
    where member.id = p_member_id
      and member.budget_id = p_budget_id
      and member.invite_status = 'active'
  )
$$;

revoke all on function public.gate_c_is_active_member_ref(uuid, uuid) from public;

create or replace function public.gate_c_validate_transaction_payload(
  p_budget_id uuid,
  p_payload jsonb
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  member_id uuid;
  split jsonb;
begin
  begin
    member_id := (p_payload ->> 'created_by_member_id')::uuid;
  exception when invalid_text_representation then
    raise exception using errcode = '22023', message = 'invalid_member_reference';
  end;
  if member_id is null then
    raise exception using errcode = '22023', message = 'invalid_member_reference';
  end if;
  if not public.gate_c_is_active_member_ref(p_budget_id, member_id) then
    raise exception using errcode = '42501', message = 'member_reference_forbidden';
  end if;

  if p_payload ? 'splits' then
    if jsonb_typeof(p_payload -> 'splits') <> 'array' then
      raise exception using errcode = '22023', message = 'invalid_member_reference';
    end if;
    for split in select value from jsonb_array_elements(p_payload -> 'splits') loop
      begin
        member_id := (split ->> 'member_id')::uuid;
      exception when invalid_text_representation then
        raise exception using errcode = '22023', message = 'invalid_member_reference';
      end;
      if member_id is null then
        raise exception using errcode = '22023', message = 'invalid_member_reference';
      end if;
      if not public.gate_c_is_active_member_ref(p_budget_id, member_id) then
        raise exception using errcode = '42501', message = 'member_reference_forbidden';
      end if;
    end loop;
  end if;
end;
$$;

create or replace function public.gate_c_validate_settlement_payload(
  p_budget_id uuid,
  p_payload jsonb
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  from_member uuid;
  to_member uuid;
begin
  begin
    from_member := (p_payload ->> 'from_member_id')::uuid;
    to_member := (p_payload ->> 'to_member_id')::uuid;
  exception when invalid_text_representation then
    raise exception using errcode = '22023', message = 'invalid_member_reference';
  end;
  if from_member is null or to_member is null or from_member = to_member then
    raise exception using errcode = '22023', message = 'invalid_member_reference';
  end if;
  if not public.gate_c_is_active_member_ref(p_budget_id, from_member)
     or not public.gate_c_is_active_member_ref(p_budget_id, to_member) then
    raise exception using errcode = '42501', message = 'member_reference_forbidden';
  end if;
end;
$$;

revoke all on function public.gate_c_validate_transaction_payload(uuid, jsonb) from public;
revoke all on function public.gate_c_validate_settlement_payload(uuid, jsonb) from public;

create or replace function public.gate_c_mutation_payload_hash(
  p_actor_user_id uuid,
  p_budget_id uuid,
  p_entity_type text,
  p_record_id uuid,
  p_operation text,
  p_expected_row_version bigint,
  p_payload jsonb
)
returns text
language sql
immutable
set search_path = pg_catalog
as $$
  select md5(concat_ws('|',
    p_actor_user_id::text,
    p_budget_id::text,
    p_entity_type,
    p_record_id::text,
    p_operation,
    coalesce(p_expected_row_version::text, '<null>'),
    coalesce(p_payload, '{}'::jsonb)::text
  ))
$$;

revoke all on function public.gate_c_mutation_payload_hash(uuid, uuid, text, uuid, text, bigint, jsonb) from public;

create or replace function public.gate_c_touch_row()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  new.updated_at := clock_timestamp();
  if tg_op = 'INSERT' then
    new.row_version := coalesce(new.row_version, 1);
  else
    new.row_version := old.row_version + 1;
  end if;
  return new;
end;
$$;

create or replace function public.gate_c_set_creator()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $$
begin
  if tg_op = 'INSERT' then
    new.created_by_user_id := coalesce(new.created_by_user_id, auth.uid());
  else
    new.created_by_user_id := old.created_by_user_id;
  end if;
  return new;
end;
$$;

revoke all on function public.gate_c_touch_row() from public;
revoke all on function public.gate_c_set_creator() from public;

drop trigger if exists a_gate_c_set_transaction_creator on public.budget_transactions;
create trigger a_gate_c_set_transaction_creator
before insert or update on public.budget_transactions
for each row execute function public.gate_c_set_creator();

drop trigger if exists a_gate_c_set_settlement_creator on public.budget_settlements;
create trigger a_gate_c_set_settlement_creator
before insert or update on public.budget_settlements
for each row execute function public.gate_c_set_creator();

do $$
begin
  if not exists (
    select 1 from pg_trigger
    where tgname = 'z_touch_budgetmate_sync_row'
      and tgrelid = 'public.budget_transactions'::regclass
      and not tgisinternal
  ) then
    create trigger z_touch_budgetmate_sync_row
    before insert or update on public.budget_transactions
    for each row execute function public.gate_c_touch_row();
  end if;
  if not exists (
    select 1 from pg_trigger
    where tgname = 'z_touch_budgetmate_sync_settlement_row'
      and tgrelid = 'public.budget_settlements'::regclass
      and not tgisinternal
  ) then
    create trigger z_touch_budgetmate_sync_settlement_row
    before insert or update on public.budget_settlements
    for each row execute function public.gate_c_touch_row();
  end if;
end
$$;

create or replace function public.gate_c_capture_transaction_tombstone()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $$
begin
  insert into public.budget_sync_tombstones (
    entity_type, budget_id, record_id, deleted_row_version,
    deleted_at, deleted_by_user_id
  )
  values (
    'transaction', old.budget_id, old.id, old.row_version + 1,
    clock_timestamp(), auth.uid()
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

create or replace function public.gate_c_capture_settlement_tombstone()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $$
begin
  insert into public.budget_sync_tombstones (
    entity_type, budget_id, record_id, deleted_row_version,
    deleted_at, deleted_by_user_id
  )
  values (
    'settlement', old.budget_id, old.id, old.row_version + 1,
    clock_timestamp(), auth.uid()
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

revoke all on function public.gate_c_capture_transaction_tombstone() from public;
revoke all on function public.gate_c_capture_settlement_tombstone() from public;

do $$
begin
  if not exists (select 1 from pg_trigger where tgname = 'z_gate_c_transaction_tombstone') then
    create trigger z_gate_c_transaction_tombstone
    after delete on public.budget_transactions
    for each row execute function public.gate_c_capture_transaction_tombstone();
  end if;
  if not exists (select 1 from pg_trigger where tgname = 'z_gate_c_settlement_tombstone') then
    create trigger z_gate_c_settlement_tombstone
    after delete on public.budget_settlements
    for each row execute function public.gate_c_capture_settlement_tombstone();
  end if;
end
$$;

-- Reads continue for active accepted members. All direct transaction and
-- settlement writes are removed; only the security-definer CAS RPCs below can
-- mutate these tables. This intentionally blocks mixed old-client writes.
drop policy if exists "Users can insert their budget transactions" on public.budget_transactions;
drop policy if exists "Users can update their budget transactions" on public.budget_transactions;
drop policy if exists "Users can delete their budget transactions" on public.budget_transactions;
drop policy if exists "Budget members can create shared transactions" on public.budget_transactions;
drop policy if exists "Budget members can update own shared transactions" on public.budget_transactions;
drop policy if exists "Budget members can delete own shared transactions" on public.budget_transactions;
drop policy if exists "Budget members can delete shared transactions" on public.budget_transactions;
drop policy if exists "Active members can create owned transactions" on public.budget_transactions;
drop policy if exists "Active members can update transactions" on public.budget_transactions;
drop policy if exists "Creators and owners can update transactions" on public.budget_transactions;
drop policy if exists "Creators and owners can delete transactions" on public.budget_transactions;
drop policy if exists "Active members can delete transactions" on public.budget_transactions;
drop policy if exists "Users can read their budget transactions" on public.budget_transactions;
drop policy if exists "Budget members can read shared transactions" on public.budget_transactions;
drop policy if exists "Active members can read transactions" on public.budget_transactions;
drop policy if exists "Gate C active members can read transactions" on public.budget_transactions;

drop policy if exists "Users can insert their budget settlements" on public.budget_settlements;
drop policy if exists "Users can update their budget settlements" on public.budget_settlements;
drop policy if exists "Users can delete their budget settlements" on public.budget_settlements;
drop policy if exists "Budget members can create shared settlements" on public.budget_settlements;
drop policy if exists "Budget members can delete shared settlements" on public.budget_settlements;
drop policy if exists "Creators and owners can update settlements" on public.budget_settlements;
drop policy if exists "Active members can create owned settlements" on public.budget_settlements;
drop policy if exists "Creators and owners can delete settlements" on public.budget_settlements;
drop policy if exists "Active members can delete settlements" on public.budget_settlements;
drop policy if exists "Users can read their budget settlements" on public.budget_settlements;
drop policy if exists "Budget members can read shared settlements" on public.budget_settlements;
drop policy if exists "Active members can read settlements" on public.budget_settlements;
drop policy if exists "Gate C active members can read settlements" on public.budget_settlements;

alter table public.budget_transactions enable row level security;
alter table public.budget_settlements enable row level security;
revoke insert, update, delete on table public.budget_transactions from public, anon, authenticated;
revoke insert, update, delete on table public.budget_settlements from public, anon, authenticated;
grant select on table public.budget_transactions to authenticated;
grant select on table public.budget_settlements to authenticated;

create policy "Gate C active members can read transactions"
on public.budget_transactions
for select
to authenticated
using (public.gate_c_is_active_member(budget_id, (select auth.uid())));

create policy "Gate C active members can read settlements"
on public.budget_settlements
for select
to authenticated
using (public.gate_c_is_active_member(budget_id, (select auth.uid())));

create or replace function public.mutate_budget_transaction(
  p_budget_id uuid,
  p_record_id uuid,
  p_expected_row_version bigint,
  p_client_mutation_id uuid,
  p_operation text,
  p_payload jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $$
declare
  caller_id uuid := auth.uid();
  operation_name text := lower(btrim(p_operation));
  existing_receipt public.budget_mutation_receipts%rowtype;
  current_row public.budget_transactions%rowtype;
  result_version bigint;
  result_deleted boolean := false;
  request_payload_hash text;
begin
  if caller_id is null then
    raise exception using errcode = '28000', message = 'An authenticated user is required.';
  end if;
  if not public.budget_data_safety_enabled() then
    raise exception using errcode = '55000', message = 'Shared-data safety writes are not enabled.';
  end if;
  if operation_name not in ('insert', 'update', 'delete') then
    raise exception using errcode = '22023', message = 'Unsupported transaction mutation.';
  end if;
  if p_client_mutation_id is null then
    raise exception using errcode = '22023', message = 'A client mutation id is required.';
  end if;
  request_payload_hash := public.gate_c_mutation_payload_hash(
    caller_id, p_budget_id, 'transaction', p_record_id,
    operation_name, p_expected_row_version, p_payload
  );
  -- Serialize retries that carry the same client id before checking the
  -- receipt, so two concurrent deliveries cannot both apply the mutation.
  perform pg_advisory_xact_lock(
    hashtextextended(p_client_mutation_id::text, 0)
  );
  if not public.gate_c_is_active_member(p_budget_id, caller_id) then
    raise exception using errcode = '42501', message = 'The caller is not an active household member.';
  end if;

  select * into existing_receipt
  from public.budget_mutation_receipts receipt
  where receipt.mutation_id = p_client_mutation_id;
  if found then
    if existing_receipt.payload_hash <> request_payload_hash then
      raise exception using errcode = 'P0001', message = 'idempotency_mismatch';
    end if;
    return jsonb_build_object(
      'record_id', existing_receipt.record_id,
      'row_version', existing_receipt.result_row_version,
      'deleted', existing_receipt.result_deleted,
      'replayed', true
    );
  end if;

  if operation_name = 'insert' then
    if p_expected_row_version is not null and p_expected_row_version <> 0 then
      raise exception using errcode = '40001', message = 'An insert must use row version zero.';
    end if;
    if exists (select 1 from public.budget_transactions where id = p_record_id) then
      raise exception using errcode = '23505', message = 'The transaction already exists.';
    end if;
    if exists (
      select 1 from public.budget_sync_tombstones
      where entity_type = 'transaction' and budget_id = p_budget_id and record_id = p_record_id
    ) then
      raise exception using errcode = 'P0002', message = 'remote_deleted';
    end if;
    perform public.gate_c_validate_transaction_payload(p_budget_id, p_payload);
    insert into public.budget_transactions (
      id, user_id, created_by_user_id, budget_id, title, amount, type,
      category, payment_method, created_by_member_id, date, occurred_on,
      created_at, recurrence_rule, splits, amount_minor_units, currency_code,
      splits_minor_units, last_mutation_id
    ) values (
      p_record_id, caller_id, caller_id, p_budget_id,
      coalesce(nullif(p_payload ->> 'title', ''), 'Untitled'),
      (p_payload ->> 'amount')::numeric,
      p_payload ->> 'type',
      p_payload ->> 'category',
      nullif(p_payload ->> 'payment_method', ''),
      (p_payload ->> 'created_by_member_id')::uuid,
      coalesce((p_payload ->> 'date')::timestamptz, clock_timestamp()),
      nullif(p_payload ->> 'occurred_on', '')::date,
      coalesce((p_payload ->> 'created_at')::timestamptz, clock_timestamp()),
      nullif(p_payload ->> 'recurrence_rule', ''),
      coalesce(p_payload -> 'splits', '[]'::jsonb),
      nullif(p_payload ->> 'amount_minor_units', '')::bigint,
      nullif(p_payload ->> 'currency_code', ''),
      p_payload -> 'splits_minor_units',
      p_client_mutation_id
    );
    select row_version into result_version
    from public.budget_transactions where id = p_record_id;
  else
    select * into current_row
    from public.budget_transactions
    where id = p_record_id and budget_id = p_budget_id
    for update;
    if not found then
      if exists (
        select 1 from public.budget_sync_tombstones
        where entity_type = 'transaction' and budget_id = p_budget_id and record_id = p_record_id
      ) then
        raise exception using errcode = 'P0002', message = 'remote_deleted';
      end if;
      raise exception using errcode = 'P0002', message = 'record_not_found';
    end if;
    if p_expected_row_version is null or current_row.row_version <> p_expected_row_version then
      raise exception using errcode = '40001', message = 'The transaction changed on another device.';
    end if;
    if not public.gate_c_is_owner(p_budget_id, caller_id)
       and (current_row.created_by_user_id is null or current_row.created_by_user_id <> caller_id) then
      raise exception using errcode = '42501', message = 'Only the authenticated creator or household owner can mutate this transaction.';
    end if;

    if operation_name = 'delete' then
      delete from public.budget_transactions where id = p_record_id;
      result_version := current_row.row_version + 1;
      result_deleted := true;
      update public.budget_sync_tombstones
      set deleted_by_mutation_id = p_client_mutation_id
      where entity_type = 'transaction'
        and budget_id = p_budget_id
        and record_id = p_record_id;
    else
      perform public.gate_c_validate_transaction_payload(p_budget_id, p_payload);
      update public.budget_transactions
      set title = coalesce(nullif(p_payload ->> 'title', ''), title),
          amount = coalesce((p_payload ->> 'amount')::numeric, amount),
          type = coalesce(nullif(p_payload ->> 'type', ''), type),
          category = coalesce(nullif(p_payload ->> 'category', ''), category),
          payment_method = nullif(p_payload ->> 'payment_method', ''),
          created_by_member_id = coalesce((p_payload ->> 'created_by_member_id')::uuid, created_by_member_id),
          date = coalesce((p_payload ->> 'date')::timestamptz, date),
          occurred_on = coalesce(nullif(p_payload ->> 'occurred_on', '')::date, occurred_on),
          recurrence_rule = nullif(p_payload ->> 'recurrence_rule', ''),
          splits = coalesce(p_payload -> 'splits', splits),
          amount_minor_units = case when p_payload ? 'amount_minor_units' then nullif(p_payload ->> 'amount_minor_units', '')::bigint else amount_minor_units end,
          currency_code = case when p_payload ? 'currency_code' then nullif(p_payload ->> 'currency_code', '') else currency_code end,
          splits_minor_units = case when p_payload ? 'splits_minor_units' then p_payload -> 'splits_minor_units' else splits_minor_units end,
          last_mutation_id = p_client_mutation_id
      where id = p_record_id;
      select row_version into result_version
      from public.budget_transactions where id = p_record_id;
    end if;
  end if;

  insert into public.budget_mutation_receipts (
    mutation_id, budget_id, actor_user_id, entity_type, record_id,
    operation, payload_hash, result_row_version, result_deleted
  ) values (
    p_client_mutation_id, p_budget_id, caller_id, 'transaction', p_record_id,
    operation_name, request_payload_hash, result_version, result_deleted
  );

  return jsonb_build_object(
    'record_id', p_record_id,
    'row_version', result_version,
    'deleted', result_deleted,
    'replayed', false
  );
end;
$$;

create or replace function public.mutate_budget_settlement(
  p_budget_id uuid,
  p_record_id uuid,
  p_expected_row_version bigint,
  p_client_mutation_id uuid,
  p_operation text,
  p_payload jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $$
declare
  caller_id uuid := auth.uid();
  operation_name text := lower(btrim(p_operation));
  existing_receipt public.budget_mutation_receipts%rowtype;
  current_row public.budget_settlements%rowtype;
  result_version bigint;
  result_deleted boolean := false;
  request_payload_hash text;
begin
  if caller_id is null then
    raise exception using errcode = '28000', message = 'An authenticated user is required.';
  end if;
  if not public.budget_data_safety_enabled() then
    raise exception using errcode = '55000', message = 'Shared-data safety writes are not enabled.';
  end if;
  if operation_name not in ('insert', 'update', 'delete') or p_client_mutation_id is null then
    raise exception using errcode = '22023', message = 'Invalid settlement mutation parameters.';
  end if;
  request_payload_hash := public.gate_c_mutation_payload_hash(
    caller_id, p_budget_id, 'settlement', p_record_id,
    operation_name, p_expected_row_version, p_payload
  );
  perform pg_advisory_xact_lock(
    hashtextextended(p_client_mutation_id::text, 0)
  );
  if not public.gate_c_is_active_member(p_budget_id, caller_id) then
    raise exception using errcode = '42501', message = 'The caller is not an active household member.';
  end if;

  select * into existing_receipt
  from public.budget_mutation_receipts receipt
  where receipt.mutation_id = p_client_mutation_id;
  if found then
    if existing_receipt.payload_hash <> request_payload_hash then
      raise exception using errcode = 'P0001', message = 'idempotency_mismatch';
    end if;
    return jsonb_build_object(
      'record_id', existing_receipt.record_id,
      'row_version', existing_receipt.result_row_version,
      'deleted', existing_receipt.result_deleted,
      'replayed', true
    );
  end if;

  if operation_name = 'insert' then
    if p_expected_row_version is not null and p_expected_row_version <> 0 then
      raise exception using errcode = '40001', message = 'An insert must use row version zero.';
    end if;
    if exists (select 1 from public.budget_settlements where id = p_record_id) then
      raise exception using errcode = '23505', message = 'The settlement already exists.';
    end if;
    if exists (
      select 1 from public.budget_sync_tombstones
      where entity_type = 'settlement' and budget_id = p_budget_id and record_id = p_record_id
    ) then
      raise exception using errcode = 'P0002', message = 'remote_deleted';
    end if;
    perform public.gate_c_validate_settlement_payload(p_budget_id, p_payload);
    insert into public.budget_settlements (
      id, user_id, created_by_user_id, budget_id, from_member_id, to_member_id,
      amount, amount_minor_units, currency_code, date, occurred_on,
      last_mutation_id
    ) values (
      p_record_id, caller_id, caller_id, p_budget_id,
      (p_payload ->> 'from_member_id')::uuid,
      (p_payload ->> 'to_member_id')::uuid,
      (p_payload ->> 'amount')::numeric,
      nullif(p_payload ->> 'amount_minor_units', '')::bigint,
      nullif(p_payload ->> 'currency_code', ''),
      coalesce((p_payload ->> 'date')::timestamptz, clock_timestamp()),
      nullif(p_payload ->> 'occurred_on', '')::date,
      p_client_mutation_id
    );
    select row_version into result_version
    from public.budget_settlements where id = p_record_id;
  else
    select * into current_row
    from public.budget_settlements
    where id = p_record_id and budget_id = p_budget_id
    for update;
    if not found then
      if exists (
        select 1 from public.budget_sync_tombstones
        where entity_type = 'settlement' and budget_id = p_budget_id and record_id = p_record_id
      ) then
        raise exception using errcode = 'P0002', message = 'remote_deleted';
      end if;
      raise exception using errcode = 'P0002', message = 'record_not_found';
    end if;
    if p_expected_row_version is null or current_row.row_version <> p_expected_row_version then
      raise exception using errcode = '40001', message = 'The settlement changed on another device.';
    end if;
    if not public.gate_c_is_owner(p_budget_id, caller_id)
       and (current_row.created_by_user_id is null or current_row.created_by_user_id <> caller_id) then
      raise exception using errcode = '42501', message = 'Only the authenticated creator or household owner can mutate this settlement.';
    end if;

    if operation_name = 'delete' then
      delete from public.budget_settlements where id = p_record_id;
      result_version := current_row.row_version + 1;
      result_deleted := true;
      update public.budget_sync_tombstones
      set deleted_by_mutation_id = p_client_mutation_id
      where entity_type = 'settlement'
        and budget_id = p_budget_id
        and record_id = p_record_id;
    else
      perform public.gate_c_validate_settlement_payload(p_budget_id, p_payload);
      update public.budget_settlements
      set from_member_id = coalesce((p_payload ->> 'from_member_id')::uuid, from_member_id),
          to_member_id = coalesce((p_payload ->> 'to_member_id')::uuid, to_member_id),
          amount = coalesce((p_payload ->> 'amount')::numeric, amount),
          amount_minor_units = case when p_payload ? 'amount_minor_units' then nullif(p_payload ->> 'amount_minor_units', '')::bigint else amount_minor_units end,
          currency_code = case when p_payload ? 'currency_code' then nullif(p_payload ->> 'currency_code', '') else currency_code end,
          date = coalesce((p_payload ->> 'date')::timestamptz, date),
          occurred_on = coalesce(nullif(p_payload ->> 'occurred_on', '')::date, occurred_on),
          last_mutation_id = p_client_mutation_id
      where id = p_record_id;
      select row_version into result_version
      from public.budget_settlements where id = p_record_id;
    end if;
  end if;

  insert into public.budget_mutation_receipts (
    mutation_id, budget_id, actor_user_id, entity_type, record_id,
    operation, payload_hash, result_row_version, result_deleted
  ) values (
    p_client_mutation_id, p_budget_id, caller_id, 'settlement', p_record_id,
    operation_name, request_payload_hash, result_version, result_deleted
  );

  return jsonb_build_object(
    'record_id', p_record_id,
    'row_version', result_version,
    'deleted', result_deleted,
    'replayed', false
  );
end;
$$;

revoke all on function public.mutate_budget_transaction(uuid, uuid, bigint, uuid, text, jsonb) from public;
revoke all on function public.mutate_budget_settlement(uuid, uuid, bigint, uuid, text, jsonb) from public;
grant execute on function public.mutate_budget_transaction(uuid, uuid, bigint, uuid, text, jsonb) to authenticated;
grant execute on function public.mutate_budget_settlement(uuid, uuid, bigint, uuid, text, jsonb) to authenticated;

drop policy if exists "Active members can read sync tombstones" on public.budget_sync_tombstones;
create policy "Active members can read sync tombstones"
on public.budget_sync_tombstones
for select
to authenticated
using (public.gate_c_is_active_member(budget_id, (select auth.uid())));

commit;

notify pgrst, 'reload schema';
