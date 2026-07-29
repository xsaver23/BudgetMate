-- PR02C1: compare legacy and exact split UUIDs semantically.
--
-- Legacy iOS clients may persist uppercase UUID strings. The exact-money
-- backfill serializes parsed UUIDs canonically in lowercase. Treating those
-- representations as text makes equal UUIDs appear contradictory.

begin;

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
  split_id uuid;
  member_id uuid;
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
    split_id := (exact_row ->> 'id')::uuid;
    member_id := (exact_row ->> 'member_id')::uuid;
    if (select count(*) from jsonb_array_elements(p_splits_minor_units) rows
        where (rows.value ->> 'id')::uuid = split_id) <> 1
       or (select count(*) from jsonb_array_elements(p_splits_minor_units) rows
        where (rows.value ->> 'member_id')::uuid = member_id) <> 1 then
      return false;
    end if;
  end loop;

  for legacy_row in select value from jsonb_array_elements(p_splits)
  loop
    split_id := (legacy_row ->> 'id')::uuid;
    member_id := (legacy_row ->> 'member_id')::uuid;
    expected_minor := public.money_bridge_minor_units(
      (legacy_row ->> 'amount')::numeric,
      household_currency
    );
    select value into exact_row
    from jsonb_array_elements(p_splits_minor_units)
    where (value ->> 'id')::uuid = split_id
      and (value ->> 'member_id')::uuid = member_id;
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

revoke all on function public.money_bridge_valid_splits_exact(
  uuid, text, numeric, bigint, jsonb, jsonb
) from public, anon, authenticated;

commit;
