#!/usr/bin/env bash
set -euo pipefail
umask 077

database="${PGDATABASE:-budgetmate_02c}"
host="${PGHOST:-localhost}"
tests_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${tests_root}/../.." && pwd)"
temporary_dir="$(mktemp -d "${TMPDIR:-/tmp}/budgetmate-gate-c-stale-lock.XXXXXX")"
transaction_holder="${temporary_dir}/transaction-holder.log"
settlement_holder="${temporary_dir}/settlement-holder.log"

cleanup() {
  if [[ -n "${transaction_pid:-}" ]]; then
    kill "${transaction_pid}" 2>/dev/null || true
    wait "${transaction_pid}" 2>/dev/null || true
  fi
  if [[ -n "${settlement_pid:-}" ]]; then
    kill "${settlement_pid}" 2>/dev/null || true
    wait "${settlement_pid}" 2>/dev/null || true
  fi
  psql --set=ON_ERROR_STOP=1 --dbname "${database}" \
    --file "${repo_root}/supabase/tests/03_shared_data_safety_stale_lock_cleanup.sql" >/dev/null 2>&1 || true
  rm -rf -- "${temporary_dir}"
}
if [[ "${host}" != "localhost" && "${host}" != "127.0.0.1" && "${host}" != "::1" ]]; then
  echo "refusing non-local database host" >&2
  exit 2
fi
case "${database}" in
  budgetmate_02c|budgetmate_gate_c_stale_diag_*) ;;
  *) echo "refusing non-rehearsal database" >&2; exit 2 ;;
esac
export PGHOST="${host}"
trap cleanup EXIT

psql --set=ON_ERROR_STOP=1 --dbname "${database}" \
  --file "${repo_root}/supabase/tests/03_shared_data_safety_stale_lock_setup.sql" >/dev/null

psql --set=ON_ERROR_STOP=1 --dbname "${database}" \
  --file "${repo_root}/supabase/tests/hold_budget_transaction_lock.sql" >"${transaction_holder}" 2>&1 &
transaction_pid=$!
sleep 0.20
psql --set=ON_ERROR_STOP=1 --dbname "${database}" \
  --file "${repo_root}/supabase/tests/03_shared_data_safety_stale_transaction_lock.sql" >/dev/null
wait "${transaction_pid}"
transaction_pid=""

psql --set=ON_ERROR_STOP=1 --dbname "${database}" \
  --file "${repo_root}/supabase/tests/hold_budget_settlement_lock.sql" >"${settlement_holder}" 2>&1 &
settlement_pid=$!
sleep 0.20
psql --set=ON_ERROR_STOP=1 --dbname "${database}" \
  --file "${repo_root}/supabase/tests/03_shared_data_safety_stale_settlement_lock.sql" >/dev/null
wait "${settlement_pid}"
settlement_pid=""

psql --set=ON_ERROR_STOP=1 --dbname "${database}" \
  --file "${repo_root}/supabase/tests/03_shared_data_safety_stale_lock_verify.sql"
