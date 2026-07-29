\set ON_ERROR_STOP on

begin;

-- The budgets trigger executes for authenticated personal-budget bootstrap.
-- Its body calls private money-bridge helpers whose EXECUTE privilege is
-- intentionally revoked from client roles. Run the trigger as its owner so
-- those helpers remain private while the trigger can enforce the invariant.
alter function public.money_bridge_validate_budget_currency()
  security definer;

alter function public.money_bridge_validate_budget_currency()
  set search_path = pg_catalog, public;

revoke all on function public.money_bridge_validate_budget_currency()
  from public, anon, authenticated;

revoke all on function public.money_bridge_budget_has_financial_history(uuid)
  from public, anon, authenticated;

comment on function public.money_bridge_validate_budget_currency() is
  'Private trigger enforcing household currency invariants with owner execution so authenticated row writes can call private money-bridge helpers.';

commit;
