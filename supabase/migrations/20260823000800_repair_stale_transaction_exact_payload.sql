-- A shared-budget screen could briefly use personal-budget currency settings
-- during startup. Treat the compatibility amount/splits as the bridge
-- authority whenever they change, so those stale exact mirrors self-heal to
-- the household currency instead of permanently blocking sync.
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
       or legacy_amount_changed
     ) then
    new.amount_minor_units := public.money_bridge_minor_units(
      new.amount, household_currency
    );
    new.currency_code := household_currency;
  end if;

  if household_currency is not null
     and (
       new.splits_minor_units is null
       or legacy_splits_changed
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
       or legacy_amount_changed
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

revoke all on function public.money_bridge_validate_transaction() from public, anon, authenticated;
revoke all on function public.money_bridge_validate_settlement() from public, anon, authenticated;

notify pgrst, 'reload schema';
