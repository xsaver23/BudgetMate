\set ON_ERROR_STOP on

begin;

do $$
declare
  trigger_is_security_definer boolean;
begin
  select procedure.prosecdef
  into trigger_is_security_definer
  from pg_proc procedure
  join pg_namespace namespace on namespace.oid = procedure.pronamespace
  where namespace.nspname = 'public'
    and procedure.proname = 'money_bridge_validate_budget_currency'
    and pg_get_function_identity_arguments(procedure.oid) = '';

  if trigger_is_security_definer is distinct from true then
    raise exception 'money_bridge_validate_budget_currency must be security definer';
  end if;

  if has_function_privilege(
    'authenticated',
    'public.money_bridge_validate_budget_currency()',
    'EXECUTE'
  ) then
    raise exception 'authenticated must not directly execute the private trigger function';
  end if;

  if has_function_privilege(
    'authenticated',
    'public.money_bridge_budget_has_financial_history(uuid)',
    'EXECUTE'
  ) then
    raise exception 'authenticated must not directly execute the private financial-history helper';
  end if;
end
$$;

grant usage on schema public to authenticated;
grant select, insert, update on public.budgets to authenticated;

set local role authenticated;
set local request.jwt.claim.sub = '90000000-0000-0000-0000-000000000003';

insert into public.budgets (
  id,
  owner_user_id,
  name,
  currency_code
)
values (
  '10000000-0000-0000-0000-000000000004',
  '90000000-0000-0000-0000-000000000003',
  'Authenticated bootstrap',
  null
);

update public.budgets
set name = 'Authenticated bootstrap updated'
where id = '10000000-0000-0000-0000-000000000004';

do $$
begin
  perform public.money_bridge_budget_has_financial_history(
    '10000000-0000-0000-0000-000000000004'
  );
  raise exception 'authenticated unexpectedly executed the private financial-history helper';
exception
  when insufficient_privilege then
    null;
end
$$;

reset role;

rollback;
