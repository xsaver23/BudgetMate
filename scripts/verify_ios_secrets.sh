#!/usr/bin/env bash
set -euo pipefail

if ! command -v git >/dev/null 2>&1; then
  echo "Secret-safety check failed: git is required for the tracked-file scan." >&2
  exit 1
fi

if ! repo_root="$(git rev-parse --show-toplevel)"; then
  echo "Secret-safety check failed: could not locate the repository root." >&2
  exit 1
fi

cd "${repo_root}"

failure=0

if ! tracked_files="$(git ls-files)"; then
  echo "Secret-safety check failed: git could not enumerate tracked files." >&2
  exit 1
fi

if git ls-files --error-unmatch -- BudgetMate/Config/Supabase.local.xcconfig >/dev/null 2>&1; then
  echo "Secret-safety check failed: Supabase.local.xcconfig is tracked." >&2
  failure=1
fi

while IFS= read -r path; do
  case "${path}" in
    .env.example|*/.env.example)
      ;;
    *)
      # Bash's regular-expression operator is available on the pinned macOS
      # runner and avoids making ripgrep an undeclared scan dependency.
      if [[ "${path}" =~ (^|/)\.env($|\.)|(^|/)(id_(rsa|dsa|ecdsa|ed25519)|[^/]+\.(pem|p12|pfx|key))$ ]]; then
        echo "Secret-safety check failed: sensitive file is tracked: ${path}" >&2
        failure=1
      fi
      ;;
  esac
done <<< "${tracked_files}"

if secret_matches="$(
  git grep -n -I -E \
    'SUPABASE_SERVICE_ROLE_KEY|service_role|sb_secret_|SUPABASE_ACCESS_TOKEN|ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----' \
    -- . ':(exclude)scripts/verify_ios_secrets.sh'
)"; then
  echo "Secret-safety check failed: obvious secret pattern found in tracked content:" >&2
  echo "${secret_matches}" >&2
  failure=1
else
  scan_status=$?
  if (( scan_status != 1 )); then
    echo "Secret-safety check failed: git content scan exited with status ${scan_status}." >&2
    exit 1
  fi
fi

if (( failure != 0 )); then
  exit 1
fi

echo "Secret-safety check passed: no tracked local config, environment file, private key, or known credential pattern found."
