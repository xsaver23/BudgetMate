-- Shared members can edit from a stale local settings snapshot. While legacy
-- category budgets remain the compatibility authority, always derive their
-- exact-money mirror when that legacy payload changes, even when an exact-aware
-- client submits a contradictory mirror. Malformed legacy values remain
-- pending (NULL exact fields) for money_bridge_preflight to report.
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
  select coalesce(
    p_category_budgets_minor_units is not null
    and public.money_bridge_settings_minor_units(
      p_category_budgets, p_monthly_budget, p_currency_code
    ) = p_category_budgets_minor_units
    and public.money_bridge_valid_visibility(p_category_budgets, p_category_visibility),
    false
  )
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
  derived_visibility jsonb;
  old_derived_visibility jsonb;
  visibility_category text;
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

  if new.category_budgets_minor_units is null or legacy_payload_changed then
    new.category_budgets_minor_units := public.money_bridge_settings_minor_units(
      new.category_budgets, new.monthly_budget, household_currency
    );
  end if;
  derived_visibility := public.money_bridge_category_visibility(
    new.category_budgets, new.monthly_budget
  );
  if new.category_visibility is null then
    new.category_visibility := derived_visibility;
  elsif tg_op = 'UPDATE' and legacy_payload_changed
        and jsonb_typeof(new.category_visibility) = 'object'
        and jsonb_typeof(derived_visibility) = 'object' then
    old_derived_visibility := public.money_bridge_category_visibility(
      old.category_budgets, old.monthly_budget
    );
    for visibility_category in
      select key
      from (
        select jsonb_object_keys(coalesce(old_derived_visibility, '{}'::jsonb)) as key
        union
        select jsonb_object_keys(derived_visibility) as key
      ) categories
      where old_derived_visibility -> key is distinct from derived_visibility -> key
    loop
      if derived_visibility ? visibility_category then
        new.category_visibility := new.category_visibility || jsonb_build_object(
          visibility_category, derived_visibility -> visibility_category
        );
      else
        new.category_visibility := new.category_visibility - visibility_category;
      end if;
    end loop;
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

revoke all on function public.money_bridge_valid_settings_exact(jsonb, numeric, text, jsonb, jsonb) from public, anon, authenticated;
revoke all on function public.money_bridge_validate_settings() from public, anon, authenticated;
