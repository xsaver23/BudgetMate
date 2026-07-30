#!/usr/bin/env bash
# Read-only preflight for the Gate C database migration.
#
# Production has 00100, 00200, and 00400 applied while 00300 is pending. The
# --include-all flag is therefore necessary for Supabase CLI to plan 00300.
# This script intentionally has no apply mode.
set -euo pipefail

if [[ "$#" -ne 0 ]]; then
  echo "Usage: $0" >&2
  echo "This is a read-only rehearsal; it has no apply mode." >&2
  exit 64
fi

for migration in \
  supabase/migrations/20260729000100_money_server_bridge.sql \
  supabase/migrations/20260729000200_money_server_bridge_uuid_case_fix.sql \
  supabase/migrations/20260729000300_shared_data_safety.sql \
  supabase/migrations/20260729000400_money_bridge_trigger_permission_fix.sql; do
  [[ -f "${migration}" ]] || {
    echo "Missing expected migration: ${migration}" >&2
    exit 66
  }
done

command -v supabase >/dev/null || {
  echo "Supabase CLI is required." >&2
  exit 69
}

echo "Reading linked migration history (no remote changes):"
supabase migration list --linked

echo
echo "Planning Gate C with the production ordering override (no remote changes):"
supabase db push --linked --include-all --dry-run

cat <<'EOF'

Dry run complete. No migration was applied and writes_enabled remains untouched.
Do not enable writes_enabled as part of this rehearsal.
EOF
