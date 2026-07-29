\set ON_ERROR_STOP on

do $$
declare
  audit record;
  exact_splits jsonb;
begin
  if (select currency_code from public.budgets where id = '10000000-0000-0000-0000-000000000001') <> 'USD'
     or (select currency_code from public.budgets where id = '10000000-0000-0000-0000-000000000002') <> 'JPY' then
    raise exception 'Household currencies were not established from legacy settings';
  end if;

  if (select amount_minor_units from public.budget_transactions where id = '20000000-0000-0000-0000-000000000001') <> 1234
     or (select amount_minor_units from public.budget_transactions where id = '20000000-0000-0000-0000-000000000002') <> 3
     or (select amount_minor_units from public.budget_settlements where id = '40000000-0000-0000-0000-000000000001') <> 2550 then
    raise exception 'Legacy record amounts did not backfill deterministically';
  end if;

  select splits_minor_units into exact_splits
  from public.budget_transactions
  where id = '20000000-0000-0000-0000-000000000001';
  if jsonb_array_length(exact_splits) <> 2
     or (
       select sum((value ->> 'amount_minor_units')::bigint)
       from jsonb_array_elements(exact_splits)
     ) <> 1234 then
    raise exception 'Split exact totals do not match the legacy transaction';
  end if;

  if (select category_budgets_minor_units ? '__hiddenCategory__restaurant'
      from public.budget_settings
      where budget_id = '10000000-0000-0000-0000-000000000001')
     or (select category_budgets_minor_units ->> 'food'
         from public.budget_settings
         where budget_id = '10000000-0000-0000-0000-000000000001') <> '1234'
     or (select category_budgets_minor_units ->> '__monthBudget__:2026-07:food'
         from public.budget_settings
         where budget_id = '10000000-0000-0000-0000-000000000001') <> '567'
     or (select category_visibility ->> 'restaurant'
         from public.budget_settings
         where budget_id = '10000000-0000-0000-0000-000000000001') <> 'hidden'
     or (select category_budgets_minor_units ->> 'other'
         from public.budget_settings
         where budget_id = '10000000-0000-0000-0000-000000000002') <> '250' then
    raise exception 'Budget amount or visibility backfill is incorrect';
  end if;

  select * into audit from public.money_bridge_preflight();
  if audit.household_currency_blocked <> 0
     or audit.transaction_blocked <> 0
     or audit.split_blocked <> 0
     or audit.settlement_blocked <> 0
     or audit.category_blocked <> 0
     or audit.exact_contradiction_rows <> 0 then
    raise exception 'Post-backfill preflight contains blocked rows: %', row_to_json(audit);
  end if;

  if has_function_privilege(
       'authenticated',
       'public.money_bridge_preflight(uuid)',
       'EXECUTE'
     )
     or not has_function_privilege(
       concat('service', '_role'),
       'public.money_bridge_preflight(uuid)',
       'EXECUTE'
     ) then
    raise exception 'Preflight privilege boundary is incorrect';
  end if;
end
$$;

-- A known old client updates only legacy fields. The trigger must recompute
-- the exact payload rather than reject the write or silently clear exact data.
update public.budget_transactions
set
  amount = 13.00,
  splits = '[{"id":"30000000-0000-0000-0000-000000000001","member_id":"80000000-0000-0000-0000-000000000001","amount":6.50},{"id":"30000000-0000-0000-0000-000000000002","member_id":"80000000-0000-0000-0000-000000000002","amount":6.50}]'
where id = '20000000-0000-0000-0000-000000000001';

update public.budget_settlements
set amount = 26.00
where id = '40000000-0000-0000-0000-000000000001';

update public.budget_settings
set category_budgets = '{"food":20,"__hiddenCategory__restaurant":1}'
where budget_id = '10000000-0000-0000-0000-000000000001';

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
values (
  '20000000-0000-0000-0000-000000000003',
  '90000000-0000-0000-0000-000000000001',
  'Old-client insert',
  1.25,
  'expense',
  'food',
  '80000000-0000-0000-0000-000000000001',
  now(),
  now(),
  '[]',
  '10000000-0000-0000-0000-000000000001'
);

do $$
begin
  if (select amount_minor_units from public.budget_transactions where id = '20000000-0000-0000-0000-000000000001') <> 1300
     or (select amount_minor_units from public.budget_settlements where id = '40000000-0000-0000-0000-000000000001') <> 2600
     or (select category_budgets_minor_units ->> 'food'
         from public.budget_settings
         where budget_id = '10000000-0000-0000-0000-000000000001') <> '2000'
     or (select amount_minor_units from public.budget_transactions where id = '20000000-0000-0000-0000-000000000003') <> 125 then
    raise exception 'Old-client writes did not preserve the exact bridge';
  end if;

  begin
    update public.budget_transactions
    set amount_minor_units = 999
    where id = '20000000-0000-0000-0000-000000000001';
    raise exception 'Contradictory transaction exact fields were accepted';
  exception
    when check_violation then null;
  end;

  begin
    update public.budget_transactions
    set splits_minor_units = '[]'::jsonb
    where id = '20000000-0000-0000-0000-000000000001';
    raise exception 'Contradictory transaction exact splits were accepted';
  exception
    when check_violation then null;
  end;

  begin
    update public.budget_settings
    set category_budgets_minor_units = '{"food":999}'::jsonb
    where budget_id = '10000000-0000-0000-0000-000000000001';
    raise exception 'Contradictory budget exact fields were accepted';
  exception
    when check_violation then null;
  end;
end
$$;

-- Currency changes must flow through settings, even while the household is empty.
do $$
begin
  begin
    update public.budgets
    set currency_code = 'EUR'
    where id = '10000000-0000-0000-0000-000000000003';
    raise exception 'Direct household currency change was accepted';
  exception
    when check_violation then null;
  end;
end
$$;

-- Currency may change through settings while the household is provably empty.
update public.budget_settings
set currency_code = 'CAD'
where budget_id = '10000000-0000-0000-0000-000000000003';

do $$
begin
  if (select currency_code from public.budgets where id = '10000000-0000-0000-0000-000000000003') <> 'CAD' then
    raise exception 'Empty-household currency change was not propagated';
  end if;
end
$$;

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
values (
  '20000000-0000-0000-0000-000000000004',
  '90000000-0000-0000-0000-000000000003',
  'Currency lock',
  1.00,
  'expense',
  'food',
  '80000000-0000-0000-0000-000000000004',
  now(),
  now(),
  '[]',
  '10000000-0000-0000-0000-000000000003'
);

do $$
begin
  begin
    update public.budget_settings
    set currency_code = 'EUR'
    where budget_id = '10000000-0000-0000-0000-000000000003';
    raise exception 'Populated-household currency change was accepted';
  exception
    when check_violation then null;
  end;
end
$$;
