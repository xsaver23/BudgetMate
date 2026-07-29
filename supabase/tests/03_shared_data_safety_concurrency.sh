#!/usr/bin/env bash
set -euo pipefail

record_transaction="20000000-0000-0000-0000-000000000098"
record_settlement="40000000-0000-0000-0000-000000000098"
transaction_mutation="aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaa0020"
settlement_mutation="aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaa0021"
transaction_payload='{"title":"concurrent","amount":7,"type":"expense","category":"food","created_by_member_id":"80000000-0000-0000-0000-000000000001","splits":[]}'
settlement_payload='{"from_member_id":"80000000-0000-0000-0000-000000000002","to_member_id":"80000000-0000-0000-0000-000000000001","amount":7}'

psql --set=ON_ERROR_STOP=1 --dbname "${PGDATABASE:-budgetmate_02c}" --command \
  "update public.budget_data_safety_config set writes_enabled = true where id = true;"

psql --set=ON_ERROR_STOP=1 --dbname "${PGDATABASE:-budgetmate_02c}" --command \
  "delete from public.budget_mutation_receipts where mutation_id in ('${transaction_mutation}', '${settlement_mutation}');
   delete from public.budget_transactions where id = '${record_transaction}';
   delete from public.budget_settlements where id = '${record_settlement}';
   delete from public.budget_sync_tombstones where record_id in ('${record_transaction}', '${record_settlement}');"

cleanup() {
  psql --set=ON_ERROR_STOP=1 --dbname "${PGDATABASE:-budgetmate_02c}" --command \
    "update public.budget_data_safety_config set writes_enabled = false where id = true;" >/dev/null
}
trap cleanup EXIT

transaction_a="$(mktemp)"
transaction_b="$(mktemp)"
settlement_a="$(mktemp)"
settlement_b="$(mktemp)"

(
  psql --set=ON_ERROR_STOP=1 --dbname "${PGDATABASE:-budgetmate_02c}" --tuples-only --no-align <<SQL
begin;
select set_config('request.jwt.claim.sub', '90000000-0000-0000-0000-000000000001', true);
select pg_sleep(0.2);
select (public.mutate_budget_transaction(
  '10000000-0000-0000-0000-000000000001',
  '${record_transaction}', 0, '${transaction_mutation}', 'insert',
  '${transaction_payload}'::jsonb
) ->> 'replayed');
commit;
SQL
) >"${transaction_a}" 2>&1 &
pid_a=$!

(
  psql --set=ON_ERROR_STOP=1 --dbname "${PGDATABASE:-budgetmate_02c}" --tuples-only --no-align <<SQL
begin;
select set_config('request.jwt.claim.sub', '90000000-0000-0000-0000-000000000001', true);
select (public.mutate_budget_transaction(
  '10000000-0000-0000-0000-000000000001',
  '${record_transaction}', 0, '${transaction_mutation}', 'insert',
  '${transaction_payload}'::jsonb
) ->> 'replayed');
commit;
SQL
) >"${transaction_b}" 2>&1 &
pid_b=$!
wait "${pid_a}"
wait "${pid_b}"

grep -q '^false$' "${transaction_a}" || grep -q '^false$' "${transaction_b}"
grep -q '^true$' "${transaction_a}" || grep -q '^true$' "${transaction_b}"
test "$(psql --set=ON_ERROR_STOP=1 --dbname "${PGDATABASE:-budgetmate_02c}" --tuples-only --no-align --command \
  "select amount from public.budget_transactions where id = '${record_transaction}';")" = "7"

(
  psql --set=ON_ERROR_STOP=1 --dbname "${PGDATABASE:-budgetmate_02c}" --tuples-only --no-align <<SQL
begin;
select set_config('request.jwt.claim.sub', '90000000-0000-0000-0000-000000000001', true);
select (public.mutate_budget_settlement(
  '10000000-0000-0000-0000-000000000001',
  '${record_settlement}', 0, '${settlement_mutation}', 'insert',
  '${settlement_payload}'::jsonb
) ->> 'replayed');
commit;
SQL
) >"${settlement_a}" 2>&1 &
settlement_pid_a=$!

(
  psql --set=ON_ERROR_STOP=1 --dbname "${PGDATABASE:-budgetmate_02c}" --tuples-only --no-align <<SQL
begin;
select set_config('request.jwt.claim.sub', '90000000-0000-0000-0000-000000000001', true);
select (public.mutate_budget_settlement(
  '10000000-0000-0000-0000-000000000001',
  '${record_settlement}', 0, '${settlement_mutation}', 'insert',
  '${settlement_payload}'::jsonb
) ->> 'replayed');
commit;
SQL
) >"${settlement_b}" 2>&1 &
settlement_pid_b=$!
wait "${settlement_pid_a}"
wait "${settlement_pid_b}"

grep -q '^false$' "${settlement_a}" || grep -q '^false$' "${settlement_b}"
grep -q '^true$' "${settlement_a}" || grep -q '^true$' "${settlement_b}"
test "$(psql --set=ON_ERROR_STOP=1 --dbname "${PGDATABASE:-budgetmate_02c}" --tuples-only --no-align --command \
  "select amount from public.budget_settlements where id = '${record_settlement}';")" = "7"

psql --set=ON_ERROR_STOP=1 --dbname "${PGDATABASE:-budgetmate_02c}" <<SQL
do \$\$
begin
  perform set_config('request.jwt.claim.sub', '90000000-0000-0000-0000-000000000001', true);
  perform public.mutate_budget_transaction(
    '10000000-0000-0000-0000-000000000001',
    '${record_transaction}', 0, '${transaction_mutation}', 'insert',
    '{"title":"different","amount":8,"type":"expense","category":"food","created_by_member_id":"80000000-0000-0000-0000-000000000001","splits":[]}'::jsonb
  );
  raise exception 'different transaction payload was accepted';
exception when sqlstate 'P0001' then
  if sqlerrm <> 'idempotency_mismatch' then raise; end if;
end
\$\$;
SQL
