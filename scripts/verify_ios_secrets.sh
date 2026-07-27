#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "${repo_root}"

failure=0

if git ls-files --error-unmatch -- BudgetMate/Config/Supabase.local.xcconfig >/dev/null 2>&1; then
  echo "Secret-safety check failed: Supabase.local.xcconfig is tracked." >&2
  failure=1
fi

while IFS= read -r path; do
  case "${path}" in
    .env.example|*/.env.example)
      ;;
    *)
      echo "Secret-safety check failed: sensitive file is tracked: ${path}" >&2
      failure=1
      ;;
  esac
done < <(
  git ls-files | rg '(^|/)\.env($|\.)|(^|/)(id_(rsa|dsa|ecdsa|ed25519)|[^/]+\.(pem|p12|pfx|key))$' || true
)

secret_matches="$(
  git grep -n -I -E \
    'SUPABASE_SERVICE_ROLE_KEY|service_role|sb_secret_|SUPABASE_ACCESS_TOKEN|ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----' \
    -- . ':(exclude)scripts/verify_ios_secrets.sh' || true
)"

if [[ -n "${secret_matches}" ]]; then
  echo "Secret-safety check failed: obvious secret pattern found in tracked content:" >&2
  echo "${secret_matches}" >&2
  failure=1
fi

if (( failure != 0 )); then
  exit 1
fi

echo "Secret-safety check passed: no tracked local config, environment file, private key, or known credential pattern found."
