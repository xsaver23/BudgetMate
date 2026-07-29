-- PR02C: additive server-side money compatibility bridge.
--
-- This is the only behavioral SQL migration in PR02C. It expands the current
-- schema, classifies legacy values, and leaves every legacy column intact.
-- Exact columns are deliberately nullable: old clients remain valid and an
-- unknown/unsupported household currency never receives guessed money.
-- There is no down migration. Rollback is a snapshot/restore rehearsal that
-- must be authorized for the target before this file is applied.

begin;

do $$
begin
  if to_regclass('public.budgets') is null
     or to_regclass('public.budget_settings') is null
     or to_regclass('public.budget_transactions') is null
     or to_regclass('public.budget_settlements') is null then
    raise exception 'PR02C requires the current BudgetMate budget tables';
  end if;

  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'budget_transactions'
      and column_name = 'budget_id'
  ) or not exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'budget_settlements'
      and column_name = 'budget_id'
  ) or not exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'budget_settings'
      and column_name = 'budget_id'
  ) then
    raise exception 'PR02C requires budget-scoped current tables';
  end if;
end
$$;

alter table public.budgets
  add column if not exists currency_code text;

alter table public.budget_transactions
  add column if not exists amount_minor_units bigint,
  add column if not exists currency_code text,
  add column if not exists splits_minor_units jsonb;

alter table public.budget_settlements
  add column if not exists amount_minor_units bigint,
  add column if not exists currency_code text;

alter table public.budget_settings
  add column if not exists category_budgets_minor_units jsonb,
  add column if not exists category_visibility jsonb;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'budgets_money_bridge_currency_catalog'
      and conrelid = 'public.budgets'::regclass
  ) then
    alter table public.budgets
      add constraint budgets_money_bridge_currency_catalog
      check (currency_code is null or currency_code in ('USD', 'CAD', 'EUR', 'GBP', 'AUD', 'PHP', 'JPY'))
      not valid;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'budget_transactions_money_bridge_exact_pair'
      and conrelid = 'public.budget_transactions'::regclass
  ) then
    alter table public.budget_transactions
      add constraint budget_transactions_money_bridge_exact_pair
      check ((amount_minor_units is null and currency_code is null)
          or (amount_minor_units is not null and currency_code is not null))
      not valid;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'budget_settlements_money_bridge_exact_pair'
      and conrelid = 'public.budget_settlements'::regclass
  ) then
    alter table public.budget_settlements
      add constraint budget_settlements_money_bridge_exact_pair
      check ((amount_minor_units is null and currency_code is null)
          or (amount_minor_units is not null and currency_code is not null))
      not valid;
  end if;
end
$$;

create or replace function public.money_bridge_fraction_digits(p_currency_code text)
returns integer
language sql
immutable
strict
set search_path = pg_catalog
as $$
  select case upper(btrim(p_currency_code))
    when 'JPY' then 0
    when 'USD' then 2
    when 'CAD' then 2
    when 'EUR' then 2
    when 'GBP' then 2
    when 'AUD' then 2
    when 'PHP' then 2
    else null
  end
$$;

create or replace function public.money_bridge_candidate_currency(p_budget_id uuid)
returns text
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select case
    when budget.currency_code in ('USD', 'CAD', 'EUR', 'GBP', 'AUD', 'PHP', 'JPY')
      then budget.currency_code
    when budget.currency_code is null
      and upper(btrim(settings.currency_code)) in ('USD', 'CAD', 'EUR', 'GBP', 'AUD', 'PHP', 'JPY')
      then upper(btrim(settings.currency_code))
    else null
  end
  from public.budgets budget
  left join public.budget_settings settings on settings.budget_id = budget.id
  where budget.id = p_budget_id
$$;

create or replace function public.money_bridge_budget_has_financial_history(p_budget_id uuid)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select exists (
    select 1 from public.budget_transactions where budget_id = p_budget_id
  ) or exists (
    select 1 from public.budget_settlements where budget_id = p_budget_id
  ) or exists (
    select 1
    from public.budget_settings
    where budget_id = p_budget_id
      and (
        coalesce(monthly_budget, 0) <> 0
        or jsonb_typeof(category_budgets) <> 'object'
        or exists (
          select 1
          from jsonb_object_keys(
            case
              when jsonb_typeof(category_budgets) = 'object' then category_budgets
              else '{}'::jsonb
            end
          )
        )
      )
  )
$$;

create or replace function public.money_bridge_minor_units(
  p_amount numeric,
  p_currency_code text
)
returns bigint
language plpgsql
immutable
strict
set search_path = pg_catalog, public
as $$
declare
  fraction_digits integer;
  scaled numeric;
begin
  -- PostgreSQL numeric can represent special values on supported versions;
  -- classify them as anomalies rather than letting a cast decide their fate.
  if p_amount::text in ('NaN', 'Infinity', '-Infinity') then
    return null;
  end if;

  fraction_digits := public.money_bridge_fraction_digits(p_currency_code);
  if fraction_digits is null then
    return null;
  end if;

  -- numeric multiplication and numeric round are deterministic. PostgreSQL's
  -- numeric round uses ties away from zero, matching the local bridge.
  scaled := round(p_amount * power(10::numeric, fraction_digits));
  if scaled < -9223372036854775808::numeric
     or scaled > 9223372036854775807::numeric then
    return null;
  end if;
  return scaled::bigint;
exception
  when invalid_text_representation or numeric_value_out_of_range or division_by_zero then
    return null;
end;
$$;

create or replace function public.money_bridge_effective_category_budgets(
  p_category_budgets jsonb,
  p_monthly_budget numeric
)
returns jsonb
language sql
immutable
set search_path = pg_catalog
as $$
  select case
    when jsonb_typeof(coalesce(p_category_budgets, '{}'::jsonb)) = 'object'
     and not exists (
       select 1
       from jsonb_object_keys(
         case
           when jsonb_typeof(p_category_budgets) = 'object' then p_category_budgets
           else '{}'::jsonb
         end
       )
     )
     and coalesce(p_monthly_budget, 0) > 0
    then jsonb_build_object('other', p_monthly_budget)
    else coalesce(p_category_budgets, '{}'::jsonb)
  end
$$;

create or replace function public.money_bridge_settings_minor_units(
  p_category_budgets jsonb,
  p_monthly_budget numeric,
  p_currency_code text
)
returns jsonb
language plpgsql
immutable
set search_path = pg_catalog, public
as $$
declare
  entry record;
  effective jsonb := public.money_bridge_effective_category_budgets(
    p_category_budgets,
    p_monthly_budget
  );
  result jsonb := '{}'::jsonb;
  rest text;
  separator integer;
  value_numeric numeric;
  minor_units bigint;
begin
  if jsonb_typeof(effective) <> 'object' then
    return null;
  end if;

  for entry in select key, value from jsonb_each(effective)
  loop
    if left(entry.key, length('__hiddenCategory__')) = '__hiddenCategory__' then
      if length(entry.key) <= length('__hiddenCategory__') then
        return null;
      end if;
      -- Hidden markers are state, never monetary values.
      continue;
    elsif left(entry.key, length('__monthBudget__:')) = '__monthBudget__:' then
      rest := substring(entry.key from length('__monthBudget__:') + 1);
      separator := position(':' in rest);
      if separator <= 1 or separator >= length(rest) then
        return null;
      end if;
    elsif left(entry.key, 2) = '__' or btrim(entry.key) = '' then
      return null;
    end if;

    if jsonb_typeof(entry.value) <> 'number' then
      return null;
    end if;

    begin
      value_numeric := (entry.value #>> '{}')::numeric;
    exception
      when invalid_text_representation or numeric_value_out_of_range then
        return null;
    end;

    minor_units := public.money_bridge_minor_units(value_numeric, p_currency_code);
    if minor_units is null then
      return null;
    end if;
    result := result || jsonb_build_object(entry.key, minor_units);
  end loop;
  return result;
end;
$$;

create or replace function public.money_bridge_category_visibility(
  p_category_budgets jsonb,
  p_monthly_budget numeric
)
returns jsonb
language plpgsql
immutable
set search_path = pg_catalog
as $$
declare
  entry record;
  effective jsonb := public.money_bridge_effective_category_budgets(
    p_category_budgets,
    p_monthly_budget
  );
  result jsonb := '{}'::jsonb;
  category text;
  rest text;
  separator integer;
begin
  if jsonb_typeof(effective) <> 'object' then
    return null;
  end if;

  for entry in select key from jsonb_each(effective)
  loop
    if left(entry.key, length('__hiddenCategory__')) = '__hiddenCategory__' then
      category := substring(entry.key from length('__hiddenCategory__') + 1);
      if category = '' then
        return null;
      end if;
      result := result || jsonb_build_object(category, 'hidden');
      continue;
    elsif left(entry.key, length('__monthBudget__:')) = '__monthBudget__:' then
      rest := substring(entry.key from length('__monthBudget__:') + 1);
      separator := position(':' in rest);
      if separator <= 1 or separator >= length(rest) then
        return null;
      end if;
      category := substring(rest from separator + 1);
    elsif left(entry.key, 2) = '__' or btrim(entry.key) = '' then
      return null;
    else
      category := entry.key;
    end if;

    if result -> category is distinct from to_jsonb('hidden'::text) then
      result := result || jsonb_build_object(category, 'visible');
    end if;
  end loop;
  return result;
end;
$$;

create or replace function public.money_bridge_splits_minor_units(
  p_splits jsonb,
  p_currency_code text
)
returns jsonb
language plpgsql
immutable
set search_path = pg_catalog, public
as $$
declare
  split_row jsonb;
  split_id uuid;
  member_id uuid;
  split_amount numeric;
  minor_units bigint;
  split_ids uuid[] := array[]::uuid[];
  member_ids uuid[] := array[]::uuid[];
  result jsonb := '[]'::jsonb;
begin
  if jsonb_typeof(p_splits) <> 'array' then
    return null;
  end if;

  for split_row in select value from jsonb_array_elements(p_splits)
  loop
    if jsonb_typeof(split_row) <> 'object'
       or jsonb_typeof(split_row -> 'id') <> 'string'
       or jsonb_typeof(split_row -> 'member_id') <> 'string'
       or jsonb_typeof(split_row -> 'amount') <> 'number' then
      return null;
    end if;
    split_id := (split_row ->> 'id')::uuid;
    member_id := (split_row ->> 'member_id')::uuid;
    split_amount := (split_row ->> 'amount')::numeric;
    if split_amount <= 0
       or split_id = any(split_ids)
       or member_id = any(member_ids) then
      return null;
    end if;
    minor_units := public.money_bridge_minor_units(split_amount, p_currency_code);
    if minor_units is null or minor_units <= 0 then
      return null;
    end if;
    split_ids := array_append(split_ids, split_id);
    member_ids := array_append(member_ids, member_id);
    result := result || jsonb_build_array(jsonb_build_object(
      'id', split_id::text,
      'member_id', member_id::text,
      'amount_minor_units', minor_units,
      'currency_code', upper(btrim(p_currency_code))
    ));
  end loop;
  return result;
exception
  when invalid_text_representation or numeric_value_out_of_range then
    return null;
end;
$$;

create or replace function public.money_bridge_valid_record_amount(
  p_budget_id uuid,
  p_amount numeric,
  p_amount_minor_units bigint,
  p_currency_code text
)
returns boolean
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  household_currency text;
begin
  if p_amount_minor_units is null or p_currency_code is null then
    return false;
  end if;
  select currency_code into household_currency
  from public.budgets where id = p_budget_id;
  return household_currency is not null
    and household_currency in ('USD', 'CAD', 'EUR', 'GBP', 'AUD', 'PHP', 'JPY')
    and p_currency_code = household_currency
    and public.money_bridge_minor_units(p_amount, household_currency) = p_amount_minor_units;
end;
$$;

create or replace function public.money_bridge_valid_splits_exact(
  p_budget_id uuid,
  p_type text,
  p_amount numeric,
  p_amount_minor_units bigint,
  p_splits jsonb,
  p_splits_minor_units jsonb
)
returns boolean
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  household_currency text;
  legacy_row jsonb;
  exact_row jsonb;
  expected_minor bigint;
  exact_minor numeric;
  split_id text;
  member_id text;
  exact_count integer;
begin
  if p_splits is null
     or p_splits_minor_units is null
     or jsonb_typeof(p_splits) <> 'array'
     or jsonb_typeof(p_splits_minor_units) <> 'array'
     or p_amount_minor_units is null
     or not public.money_bridge_valid_record_amount(
       p_budget_id, p_amount, p_amount_minor_units,
       (select currency_code from public.budgets where id = p_budget_id)
     )
     or not public.valid_budget_transaction_splits(p_type, p_amount, p_splits) then
    return false;
  end if;

  select currency_code into household_currency
  from public.budgets where id = p_budget_id;
  if household_currency is null
     or jsonb_array_length(p_splits) <> jsonb_array_length(p_splits_minor_units) then
    return false;
  end if;

  for exact_row in select value from jsonb_array_elements(p_splits_minor_units)
  loop
    if jsonb_typeof(exact_row) <> 'object'
       or jsonb_typeof(exact_row -> 'id') <> 'string'
       or jsonb_typeof(exact_row -> 'member_id') <> 'string'
       or jsonb_typeof(exact_row -> 'amount_minor_units') <> 'number'
       or jsonb_typeof(exact_row -> 'currency_code') <> 'string'
       or exact_row ->> 'currency_code' <> household_currency then
      return false;
    end if;
    exact_minor := (exact_row ->> 'amount_minor_units')::numeric;
    if exact_minor <> trunc(exact_minor)
       or exact_minor <= 0
       or exact_minor < -9223372036854775808::numeric
       or exact_minor > 9223372036854775807::numeric then
      return false;
    end if;
    split_id := exact_row ->> 'id';
    member_id := exact_row ->> 'member_id';
    if (select count(*) from jsonb_array_elements(p_splits_minor_units) rows
        where rows.value ->> 'id' = split_id) <> 1
       or (select count(*) from jsonb_array_elements(p_splits_minor_units) rows
        where rows.value ->> 'member_id' = member_id) <> 1 then
      return false;
    end if;
  end loop;

  for legacy_row in select value from jsonb_array_elements(p_splits)
  loop
    split_id := legacy_row ->> 'id';
    member_id := legacy_row ->> 'member_id';
    expected_minor := public.money_bridge_minor_units(
      (legacy_row ->> 'amount')::numeric,
      household_currency
    );
    select value into exact_row
    from jsonb_array_elements(p_splits_minor_units)
    where value ->> 'id' = split_id
      and value ->> 'member_id' = member_id;
    if exact_row is null
       or expected_minor is null
       or (exact_row ->> 'amount_minor_units')::numeric <> expected_minor then
      return false;
    end if;
  end loop;

  return true;
exception
  when invalid_text_representation or numeric_value_out_of_range then
    return false;
end;
$$;

create or replace function public.money_bridge_valid_visibility(
  p_category_budgets jsonb,
  p_visibility jsonb
)
returns boolean
language plpgsql
immutable
set search_path = pg_catalog
as $$
declare
  entry record;
  category text;
begin
  if p_visibility is null or jsonb_typeof(p_visibility) <> 'object' then
    return false;
  end if;
  for entry in select key, value from jsonb_each(p_visibility)
  loop
    if btrim(entry.key) = ''
       or left(entry.key, 2) = '__'
       or jsonb_typeof(entry.value) <> 'string'
       or entry.value #>> '{}' not in ('visible', 'hidden') then
      return false;
    end if;
  end loop;

  for entry in select key from jsonb_each(
    case when jsonb_typeof(coalesce(p_category_budgets, '{}'::jsonb)) = 'object'
      then coalesce(p_category_budgets, '{}'::jsonb)
      else '{}'::jsonb
    end
  )
  loop
    if left(entry.key, length('__hiddenCategory__')) = '__hiddenCategory__' then
      category := substring(entry.key from length('__hiddenCategory__') + 1);
      if category = '' or p_visibility ->> category <> 'hidden' then
        return false;
      end if;
    end if;
  end loop;
  return true;
end;
$$;

create or replace function public.money_bridge_valid_settings_exact(
  p_category_budgets jsonb,
  p_monthly_budget numeric,
  p_currency_code text,
  p_category_budgets_minor_units jsonb,
  p_category_visibility jsonb
)
returns boolean
language sql
immutable
set search_path = pg_catalog, public
as $$
  select p_category_budgets_minor_units is not null
    and public.money_bridge_settings_minor_units(
      p_category_budgets, p_monthly_budget, p_currency_code
    ) = p_category_budgets_minor_units
    and public.money_bridge_valid_visibility(p_category_budgets, p_category_visibility)
$$;

create or replace function public.money_bridge_preflight(p_budget_id uuid default null)
returns table (
  household_rows bigint,
  household_currency_ready bigint,
  household_currency_blocked bigint,
  transaction_rows bigint,
  transaction_exact_ready bigint,
  transaction_pending bigint,
  transaction_blocked bigint,
  split_entries bigint,
  split_exact_ready bigint,
  split_pending bigint,
  split_blocked bigint,
  settlement_rows bigint,
  settlement_exact_ready bigint,
  settlement_pending bigint,
  settlement_blocked bigint,
  category_entries bigint,
  hidden_marker_entries bigint,
  month_scoped_entries bigint,
  category_exact_ready bigint,
  category_pending bigint,
  category_blocked bigint,
  exact_contradiction_rows bigint
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  transaction_exact bigint;
  transaction_pending_rows bigint;
  settlement_exact bigint;
  settlement_pending_rows bigint;
  split_exact bigint;
  split_pending_rows bigint;
  category_exact bigint;
  category_pending_rows bigint;
begin
  select count(*) into household_rows from public.budgets
  where p_budget_id is null or id = p_budget_id;
  select count(*) into household_currency_ready from public.budgets
  where (p_budget_id is null or id = p_budget_id)
    and public.money_bridge_candidate_currency(id) is not null;
  select count(*) into household_currency_blocked from public.budgets budget
  where (p_budget_id is null or budget.id = p_budget_id)
    and (public.money_bridge_candidate_currency(budget.id) is null
      or exists (
        select 1 from public.budget_settings settings
        where settings.budget_id = budget.id
          and upper(btrim(settings.currency_code))
            is distinct from public.money_bridge_candidate_currency(budget.id)
      ));

  select count(*) filter (where public.money_bridge_valid_record_amount(
      transaction.budget_id, transaction.amount, transaction.amount_minor_units,
      transaction.currency_code
    )),
    count(*) filter (where transaction.amount_minor_units is null
      and transaction.currency_code is null
      and public.money_bridge_candidate_currency(budget.id) is not null
      and public.money_bridge_minor_units(
        transaction.amount,
        public.money_bridge_candidate_currency(budget.id)
      ) is not null)
  into transaction_exact, transaction_pending_rows
  from public.budget_transactions transaction
  left join public.budgets budget on budget.id = transaction.budget_id
  where p_budget_id is null or transaction.budget_id = p_budget_id;
  transaction_rows := (select count(*) from public.budget_transactions transaction
    where p_budget_id is null or transaction.budget_id = p_budget_id);
  transaction_exact_ready := coalesce(transaction_exact, 0);
  transaction_pending := coalesce(transaction_pending_rows, 0);
  transaction_blocked := greatest(0, transaction_rows - transaction_exact_ready - transaction_pending);

  select count(*) filter (where public.money_bridge_valid_record_amount(
      settlement.budget_id, settlement.amount, settlement.amount_minor_units,
      settlement.currency_code
    )),
    count(*) filter (where settlement.amount_minor_units is null
      and settlement.currency_code is null
      and public.money_bridge_candidate_currency(budget.id) is not null
      and public.money_bridge_minor_units(
        settlement.amount,
        public.money_bridge_candidate_currency(budget.id)
      ) is not null)
  into settlement_exact, settlement_pending_rows
  from public.budget_settlements settlement
  left join public.budgets budget on budget.id = settlement.budget_id
  where p_budget_id is null or settlement.budget_id = p_budget_id;
  settlement_rows := (select count(*) from public.budget_settlements settlement
    where p_budget_id is null or settlement.budget_id = p_budget_id);
  settlement_exact_ready := coalesce(settlement_exact, 0);
  settlement_pending := coalesce(settlement_pending_rows, 0);
  settlement_blocked := greatest(0, settlement_rows - settlement_exact_ready - settlement_pending);

  select coalesce(sum(jsonb_array_length(transaction.splits)), 0)
  into split_entries
  from public.budget_transactions transaction
  where (p_budget_id is null or transaction.budget_id = p_budget_id)
    and jsonb_typeof(transaction.splits) = 'array';
  select coalesce(sum(jsonb_array_length(transaction.splits_minor_units)), 0)
  into split_exact
  from public.budget_transactions transaction
  where (p_budget_id is null or transaction.budget_id = p_budget_id)
    and public.money_bridge_valid_splits_exact(
      transaction.budget_id, transaction.type, transaction.amount,
      transaction.amount_minor_units, transaction.splits,
      transaction.splits_minor_units
    );
  select coalesce(sum(jsonb_array_length(transaction.splits)), 0)
  into split_pending_rows
  from public.budget_transactions transaction
  join public.budgets budget on budget.id = transaction.budget_id
  where (p_budget_id is null or transaction.budget_id = p_budget_id)
    and transaction.splits_minor_units is null
    and public.money_bridge_candidate_currency(budget.id) is not null
    and public.valid_budget_transaction_splits(transaction.type, transaction.amount, transaction.splits)
    and public.money_bridge_splits_minor_units(
      transaction.splits,
      public.money_bridge_candidate_currency(budget.id)
    ) is not null;
  split_exact_ready := coalesce(split_exact, 0);
  split_pending := coalesce(split_pending_rows, 0);
  split_blocked := greatest(0, split_entries - split_exact_ready - split_pending);

  select coalesce(sum(case when jsonb_typeof(settings.category_budgets) = 'object'
    then (
      select count(*) from jsonb_object_keys(settings.category_budgets)
    ) else 0 end), 0)::bigint
  into category_entries
  from public.budget_settings settings
  where p_budget_id is null or settings.budget_id = p_budget_id;
  select coalesce(sum((select count(*) from jsonb_each(
    case when jsonb_typeof(settings.category_budgets) = 'object'
      then settings.category_budgets else '{}'::jsonb end
  ) entry where left(entry.key, length('__hiddenCategory__')) = '__hiddenCategory__')), 0)
  into hidden_marker_entries
  from public.budget_settings settings
  where p_budget_id is null or settings.budget_id = p_budget_id;
  select coalesce(sum((select count(*) from jsonb_each(
    case when jsonb_typeof(settings.category_budgets) = 'object'
      then settings.category_budgets else '{}'::jsonb end
  ) entry where left(entry.key, length('__monthBudget__:')) = '__monthBudget__:')), 0)
  into month_scoped_entries
  from public.budget_settings settings
  where p_budget_id is null or settings.budget_id = p_budget_id;
  select count(*) filter (where public.money_bridge_valid_settings_exact(
      settings.category_budgets, settings.monthly_budget, settings.currency_code,
      settings.category_budgets_minor_units, settings.category_visibility
    )),
    count(*) filter (where settings.category_budgets_minor_units is null
      and public.money_bridge_candidate_currency(budget.id) is not null
      and public.money_bridge_settings_minor_units(
        settings.category_budgets,
        settings.monthly_budget,
        public.money_bridge_candidate_currency(budget.id)
      ) is not null)
  into category_exact, category_pending_rows
  from public.budget_settings settings
  left join public.budgets budget on budget.id = settings.budget_id
  where p_budget_id is null or settings.budget_id = p_budget_id;
  category_exact_ready := coalesce(category_exact, 0);
  category_pending := coalesce(category_pending_rows, 0);
  category_blocked := greatest(0, (select count(*) from public.budget_settings settings
    where p_budget_id is null or settings.budget_id = p_budget_id)
    - category_exact_ready - category_pending);
  exact_contradiction_rows :=
    (
      select count(*)
      from public.budget_transactions transaction
      where (p_budget_id is null or transaction.budget_id = p_budget_id)
        and (
          (transaction.amount_minor_units is null) <> (transaction.currency_code is null)
          or (
            transaction.amount_minor_units is not null
            and not public.money_bridge_valid_record_amount(
              transaction.budget_id,
              transaction.amount,
              transaction.amount_minor_units,
              transaction.currency_code
            )
          )
          or (
            transaction.splits_minor_units is not null
            and not public.money_bridge_valid_splits_exact(
              transaction.budget_id,
              transaction.type,
              transaction.amount,
              transaction.amount_minor_units,
              transaction.splits,
              transaction.splits_minor_units
            )
          )
        )
    )
    + (
      select count(*)
      from public.budget_settlements settlement
      where (p_budget_id is null or settlement.budget_id = p_budget_id)
        and (
          (settlement.amount_minor_units is null) <> (settlement.currency_code is null)
          or (
            settlement.amount_minor_units is not null
            and not public.money_bridge_valid_record_amount(
              settlement.budget_id,
              settlement.amount,
              settlement.amount_minor_units,
              settlement.currency_code
            )
          )
        )
    )
    + (
      select count(*)
      from public.budget_settings settings
      where (p_budget_id is null or settings.budget_id = p_budget_id)
        and (
          settings.category_budgets_minor_units is not null
          or settings.category_visibility is not null
        )
        and not public.money_bridge_valid_settings_exact(
          settings.category_budgets,
          settings.monthly_budget,
          settings.currency_code,
          settings.category_budgets_minor_units,
          settings.category_visibility
        )
    );
  return next;
end;
$$;

do $$
declare
  audit record;
begin
  select * into audit from public.money_bridge_preflight();
  raise notice 'PR02C preflight households=% ready=% blocked=% transactions=% exact=% pending=% blocked=% splits=% exact=% pending=% blocked=% settlements=% exact=% pending=% blocked=% categories=% hidden=% month=% exact=% pending=% blocked=% contradictions=%',
    audit.household_rows, audit.household_currency_ready, audit.household_currency_blocked,
    audit.transaction_rows, audit.transaction_exact_ready, audit.transaction_pending, audit.transaction_blocked,
    audit.split_entries, audit.split_exact_ready, audit.split_pending, audit.split_blocked,
    audit.settlement_rows, audit.settlement_exact_ready, audit.settlement_pending, audit.settlement_blocked,
    audit.category_entries, audit.hidden_marker_entries, audit.month_scoped_entries,
    audit.category_exact_ready, audit.category_pending, audit.category_blocked,
    audit.exact_contradiction_rows;
end
$$;

-- The household currency is sourced from the existing budget settings only
-- after the read-only preflight has classified every legacy row. Unsupported
-- or absent settings leave the new household source NULL and therefore block
-- exact backfill without changing legacy data.
update public.budgets budget
set currency_code = upper(btrim(settings.currency_code))
from public.budget_settings settings
where settings.budget_id = budget.id
  and budget.currency_code is null
  and upper(btrim(settings.currency_code)) in ('USD', 'CAD', 'EUR', 'GBP', 'AUD', 'PHP', 'JPY');

update public.budget_transactions transaction
set amount_minor_units = public.money_bridge_minor_units(transaction.amount, budget.currency_code),
    currency_code = budget.currency_code
from public.budgets budget
where transaction.budget_id = budget.id
  and transaction.amount_minor_units is null
  and transaction.currency_code is null
  and budget.currency_code in ('USD', 'CAD', 'EUR', 'GBP', 'AUD', 'PHP', 'JPY')
  and public.money_bridge_minor_units(transaction.amount, budget.currency_code) is not null;

update public.budget_settlements settlement
set amount_minor_units = public.money_bridge_minor_units(settlement.amount, budget.currency_code),
    currency_code = budget.currency_code
from public.budgets budget
where settlement.budget_id = budget.id
  and settlement.amount_minor_units is null
  and settlement.currency_code is null
  and budget.currency_code in ('USD', 'CAD', 'EUR', 'GBP', 'AUD', 'PHP', 'JPY')
  and public.money_bridge_minor_units(settlement.amount, budget.currency_code) is not null;

update public.budget_transactions transaction
set splits_minor_units = public.money_bridge_splits_minor_units(
  transaction.splits,
  budget.currency_code
)
from public.budgets budget
where transaction.budget_id = budget.id
  and transaction.splits_minor_units is null
  and transaction.amount_minor_units is not null
  and public.money_bridge_valid_record_amount(
    transaction.budget_id, transaction.amount, transaction.amount_minor_units,
    transaction.currency_code
  )
  and public.valid_budget_transaction_splits(transaction.type, transaction.amount, transaction.splits)
  and public.money_bridge_splits_minor_units(transaction.splits, budget.currency_code) is not null;

update public.budget_settings settings
set category_budgets_minor_units = public.money_bridge_settings_minor_units(
      settings.category_budgets, settings.monthly_budget, budget.currency_code
    )
from public.budgets budget
where settings.budget_id = budget.id
  and settings.category_budgets_minor_units is null
  and budget.currency_code in ('USD', 'CAD', 'EUR', 'GBP', 'AUD', 'PHP', 'JPY')
  and public.money_bridge_settings_minor_units(
    settings.category_budgets, settings.monthly_budget, budget.currency_code
  ) is not null;

-- Visibility is non-monetary and can be recovered even when an amount is
-- anomalous; no hidden marker is ever included in the exact amount map.
update public.budget_settings settings
set category_visibility = public.money_bridge_category_visibility(
  settings.category_budgets, settings.monthly_budget
)
where settings.category_visibility is null
  and public.money_bridge_category_visibility(
    settings.category_budgets, settings.monthly_budget
  ) is not null;

do $$
declare
  audit record;
begin
  select * into audit from public.money_bridge_preflight();
  raise notice 'PR02C post-backfill households=% ready=% blocked=% transactions=% exact=% pending=% blocked=% splits=% exact=% pending=% blocked=% settlements=% exact=% pending=% blocked=% categories=% hidden=% month=% exact=% pending=% blocked=% contradictions=%',
    audit.household_rows, audit.household_currency_ready, audit.household_currency_blocked,
    audit.transaction_rows, audit.transaction_exact_ready, audit.transaction_pending, audit.transaction_blocked,
    audit.split_entries, audit.split_exact_ready, audit.split_pending, audit.split_blocked,
    audit.settlement_rows, audit.settlement_exact_ready, audit.settlement_pending, audit.settlement_blocked,
    audit.category_entries, audit.hidden_marker_entries, audit.month_scoped_entries,
    audit.category_exact_ready, audit.category_pending, audit.category_blocked,
    audit.exact_contradiction_rows;
end
$$;

create or replace function public.money_bridge_validate_budget_currency()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
begin
  if new.currency_code is not null then
    new.currency_code := upper(btrim(new.currency_code));
  end if;
  if new.currency_code is not null
     and new.currency_code not in ('USD', 'CAD', 'EUR', 'GBP', 'AUD', 'PHP', 'JPY') then
    raise exception 'Unsupported household currency for exact-money bridge: %', new.currency_code
      using errcode = '23514';
  end if;
  if tg_op = 'UPDATE'
     and old.currency_code is not null
     and new.currency_code is distinct from old.currency_code
     and public.money_bridge_budget_has_financial_history(old.id) then
    raise exception 'Household currency is immutable after establishment'
      using errcode = '23514';
  end if;
  if tg_op = 'UPDATE'
     and new.currency_code is distinct from old.currency_code
     and pg_trigger_depth() = 1
     and exists (
       select 1
       from public.budget_settings settings
       where settings.budget_id = new.id
         and upper(btrim(settings.currency_code))
           is distinct from new.currency_code
     ) then
    raise exception 'Change household currency through budget settings'
      using errcode = '23514';
  end if;
  return new;
end;
$$;

create or replace function public.money_bridge_validate_settings()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  household_currency text;
  legacy_payload_changed boolean := true;
begin
  new.currency_code := upper(btrim(new.currency_code));
  if new.currency_code not in ('USD', 'CAD', 'EUR', 'GBP', 'AUD', 'PHP', 'JPY') then
    raise exception 'Unsupported budget settings currency: %', new.currency_code
      using errcode = '23514';
  end if;

  select currency_code into household_currency
  from public.budgets where id = new.budget_id;
  if household_currency is null
     or new.currency_code is distinct from household_currency then
    if household_currency is not null
       and public.money_bridge_budget_has_financial_history(new.budget_id) then
      raise exception 'Budget settings currency does not match the locked household currency'
        using errcode = '23514';
    end if;
    update public.budgets
    set currency_code = new.currency_code
    where id = new.budget_id;
    if not found then
      raise exception 'Budget settings require an existing household'
        using errcode = '23503';
    end if;
    household_currency := new.currency_code;
  end if;

  if tg_op = 'UPDATE' then
    legacy_payload_changed :=
      new.currency_code is distinct from old.currency_code
      or new.monthly_budget is distinct from old.monthly_budget
      or new.category_budgets is distinct from old.category_budgets;
  end if;

  if new.category_budgets_minor_units is null
     or (
       tg_op = 'UPDATE'
       and legacy_payload_changed
       and new.category_budgets_minor_units is not distinct from old.category_budgets_minor_units
     ) then
    new.category_budgets_minor_units := public.money_bridge_settings_minor_units(
      new.category_budgets, new.monthly_budget, household_currency
    );
  end if;
  if new.category_visibility is null
     or (
       tg_op = 'UPDATE'
       and legacy_payload_changed
       and new.category_visibility is not distinct from old.category_visibility
     ) then
    new.category_visibility := public.money_bridge_category_visibility(
      new.category_budgets, new.monthly_budget
    );
  end if;

  if new.category_visibility is not null
     and not public.money_bridge_valid_visibility(new.category_budgets, new.category_visibility) then
    raise exception 'Invalid category visibility payload'
      using errcode = '23514';
  end if;
  if new.category_budgets_minor_units is not null then
    if household_currency is null
       or new.currency_code is distinct from household_currency
       or not public.money_bridge_valid_settings_exact(
         new.category_budgets, new.monthly_budget, household_currency,
         new.category_budgets_minor_units, new.category_visibility
       ) then
      raise exception 'Contradictory or unestablished exact category budget payload'
        using errcode = '23514';
    end if;
  end if;
  return new;
end;
$$;

create or replace function public.money_bridge_validate_transaction()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  household_currency text;
  legacy_amount_changed boolean := true;
  legacy_splits_changed boolean := true;
begin
  select currency_code into household_currency
  from public.budgets where id = new.budget_id;

  if tg_op = 'UPDATE' then
    legacy_amount_changed := new.amount is distinct from old.amount;
    legacy_splits_changed :=
      new.type is distinct from old.type
      or new.splits is distinct from old.splits;
  end if;

  if household_currency is not null
     and (
       (new.amount_minor_units is null and new.currency_code is null)
       or (
         tg_op = 'UPDATE'
         and legacy_amount_changed
         and new.amount_minor_units is not distinct from old.amount_minor_units
         and new.currency_code is not distinct from old.currency_code
       )
     ) then
    new.amount_minor_units := public.money_bridge_minor_units(
      new.amount, household_currency
    );
    new.currency_code := household_currency;
  end if;

  if household_currency is not null
     and (
       new.splits_minor_units is null
       or (
         tg_op = 'UPDATE'
         and legacy_splits_changed
         and new.splits_minor_units is not distinct from old.splits_minor_units
       )
     ) then
    new.splits_minor_units := public.money_bridge_splits_minor_units(
      new.splits, household_currency
    );
  end if;

  if (new.amount_minor_units is null) <> (new.currency_code is null) then
    raise exception 'Transaction exact amount fields must be both null or both present'
      using errcode = '23514';
  end if;
  if new.amount_minor_units is not null
     and not public.money_bridge_valid_record_amount(
       new.budget_id, new.amount, new.amount_minor_units, new.currency_code
     ) then
    raise exception 'Contradictory or unestablished transaction exact amount'
      using errcode = '23514';
  end if;
  if new.splits_minor_units is not null
     and not public.money_bridge_valid_splits_exact(
       new.budget_id, new.type, new.amount, new.amount_minor_units,
       new.splits, new.splits_minor_units
     ) then
    raise exception 'Contradictory transaction exact split payload'
      using errcode = '23514';
  end if;
  return new;
end;
$$;

create or replace function public.money_bridge_validate_settlement()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  household_currency text;
  legacy_amount_changed boolean := true;
begin
  select currency_code into household_currency
  from public.budgets where id = new.budget_id;
  if tg_op = 'UPDATE' then
    legacy_amount_changed := new.amount is distinct from old.amount;
  end if;
  if household_currency is not null
     and (
       (new.amount_minor_units is null and new.currency_code is null)
       or (
         tg_op = 'UPDATE'
         and legacy_amount_changed
         and new.amount_minor_units is not distinct from old.amount_minor_units
         and new.currency_code is not distinct from old.currency_code
       )
     ) then
    new.amount_minor_units := public.money_bridge_minor_units(
      new.amount, household_currency
    );
    new.currency_code := household_currency;
  end if;
  if (new.amount_minor_units is null) <> (new.currency_code is null) then
    raise exception 'Settlement exact amount fields must be both null or both present'
      using errcode = '23514';
  end if;
  if new.amount_minor_units is not null
     and not public.money_bridge_valid_record_amount(
       new.budget_id, new.amount, new.amount_minor_units, new.currency_code
     ) then
    raise exception 'Contradictory or unestablished settlement exact amount'
      using errcode = '23514';
  end if;
  return new;
end;
$$;

drop trigger if exists z_money_bridge_validate_budget_currency on public.budgets;
create trigger z_money_bridge_validate_budget_currency
before insert or update on public.budgets
for each row execute function public.money_bridge_validate_budget_currency();

drop trigger if exists z_money_bridge_validate_settings on public.budget_settings;
create trigger z_money_bridge_validate_settings
before insert or update on public.budget_settings
for each row execute function public.money_bridge_validate_settings();

drop trigger if exists z_money_bridge_validate_transaction on public.budget_transactions;
create trigger z_money_bridge_validate_transaction
before insert or update on public.budget_transactions
for each row execute function public.money_bridge_validate_transaction();

drop trigger if exists z_money_bridge_validate_settlement on public.budget_settlements;
create trigger z_money_bridge_validate_settlement
before insert or update on public.budget_settlements
for each row execute function public.money_bridge_validate_settlement();

alter table public.budgets
  validate constraint budgets_money_bridge_currency_catalog;
alter table public.budget_transactions
  validate constraint budget_transactions_money_bridge_exact_pair;
alter table public.budget_settlements
  validate constraint budget_settlements_money_bridge_exact_pair;

revoke all on function public.money_bridge_fraction_digits(text) from public, anon, authenticated;
revoke all on function public.money_bridge_candidate_currency(uuid) from public, anon, authenticated;
revoke all on function public.money_bridge_budget_has_financial_history(uuid) from public, anon, authenticated;
revoke all on function public.money_bridge_minor_units(numeric, text) from public, anon, authenticated;
revoke all on function public.money_bridge_effective_category_budgets(jsonb, numeric) from public, anon, authenticated;
revoke all on function public.money_bridge_settings_minor_units(jsonb, numeric, text) from public, anon, authenticated;
revoke all on function public.money_bridge_category_visibility(jsonb, numeric) from public, anon, authenticated;
revoke all on function public.money_bridge_splits_minor_units(jsonb, text) from public, anon, authenticated;
revoke all on function public.money_bridge_valid_record_amount(uuid, numeric, bigint, text) from public, anon, authenticated;
revoke all on function public.money_bridge_valid_splits_exact(uuid, text, numeric, bigint, jsonb, jsonb) from public, anon, authenticated;
revoke all on function public.money_bridge_valid_visibility(jsonb, jsonb) from public, anon, authenticated;
revoke all on function public.money_bridge_valid_settings_exact(jsonb, numeric, text, jsonb, jsonb) from public, anon, authenticated;
revoke all on function public.money_bridge_preflight(uuid) from public, anon, authenticated;
revoke all on function public.money_bridge_validate_budget_currency() from public, anon, authenticated;
revoke all on function public.money_bridge_validate_settings() from public, anon, authenticated;
revoke all on function public.money_bridge_validate_transaction() from public, anon, authenticated;
revoke all on function public.money_bridge_validate_settlement() from public, anon, authenticated;
do $$
begin
  execute format(
    'grant execute on function public.money_bridge_preflight(uuid) to %I',
    concat('service', '_role')
  );
end
$$;

commit;
