# Gate C Controlled Rollout Plan

## Outcome

Enable Gate C transaction and settlement safety for the controlled BudgetMate
beta without broadening product scope. Gate C uses authenticated,
idempotent compare-and-set RPCs, durable mutation receipts, and tombstones.

The rollout is complete only when the production migration, server switch,
approved client configuration, authenticated two-account matrix, and hosted
release checks are all green on identified commits.

## Current state

- Migrations `20260729000100`, `20260729000200`, and
  `20260729000400` are deployed.
- Migration `20260729000300_shared_data_safety.sql` is not deployed.
- The Gate C server configuration does not exist in production yet.
- `MoneyServerBridgeRollout` and `SharedDataSafetyGate` default to disabled.
- Gate D keeps unfinished invitation, leave, ownership-transfer, clear-all,
  and account-deletion actions unavailable.

## Scope guardrails

- No new product feature, UI redesign, schema redesign, or unrelated cleanup.
- One additive server migration: the already-merged `00300`.
- No destructive down migration and no production restore unless a verified
  incident requires the pre-rollout backup.
- Server writes stay disabled while the migration is deployed and verified.
- Client activation stays disabled until the server migration and server
  configuration are verified.
- Never log passwords, access tokens, private transaction text, or amounts.
- Test only dedicated QA accounts and records.
- Stop for any P0/P1 data loss, authorization bypass, cross-budget leakage,
  duplicate mutation, stale-write acceptance, migration mismatch, crash, or
  inability to disable writes immediately.

## Chunk 1 — Server rehearsal and disabled-safe deployment

Owner: Gate C server track.

1. Verify the live migration ledger, schema prerequisites, policies, function
   signatures, and a current recoverable backup.
2. Rehearse applying `00300` after already-applied `00400`. Supabase requires
   an explicit `--include-all` because `00300` sorts before the latest remote
   migration.
3. Prove migration replay/idempotency, PostgreSQL contract tests,
   concurrency tests, old-client read behavior, and rollback restore.
4. Dry-run the exact production command and prove it selects only `00300`.
5. With separate owner approval, deploy `00300` while
   `writes_enabled = false`.
6. Postflight must prove:
   - Gate C reports disabled.
   - Existing authorized reads still work.
   - Direct transaction and settlement writes are denied.
   - Gate C RPC writes fail closed with the documented disabled error.
   - Migration `00400` trigger permissions remain correct.

Exit criterion: production has `00300`, the write switch is false, and all
disabled-state checks pass.

## Chunk 2 — Fail-closed client activation

Owner: Gate C client track.

1. Replace hard-coded rollout decisions with one explicit, testable
   configuration contract.
2. Default every ordinary Debug and Release build to disabled.
3. Require money-bridge compatibility and Gate C activation together; any
   missing or inconsistent value fails closed.
4. Verify pending local mutations keep their stable mutation IDs while
   disabled and route only through Gate C RPCs when enabled.
5. Cover insert, update, delete, retry, conflict mapping, capability rules,
   account/budget switching, and accessible read-only messaging.
6. Run focused tests, full unit/UI suites, iPhone/iPad builds, Release
   analyze/archive, secret scan, and project-integrity checks.

Exit criterion: a reviewed candidate can be explicitly enabled without
changing source again, while default builds remain disabled.

## Chunk 3 — Controlled authenticated QA window

Owner: independent Gate C QA track.

Use two dedicated confirmed QA accounts. Do not touch owner data.

Required cases:

- Personal and shared-budget authorized reads.
- Transaction and settlement insert/update/delete through RPC only.
- Exact-money and legacy compatibility fields reconcile.
- Same mutation ID plus same request replays exactly once.
- Same mutation ID plus different request is rejected.
- Stale row version is rejected.
- Removed, inactive, nonmember, and cross-budget actors are denied.
- Direct PostgREST writes remain denied.
- Deletes create durable, correctly scoped tombstones.
- Offline retry and relaunch preserve pending mutations and IDs.
- Account and budget switching cannot leak or apply queued writes elsewhere.
- Disabling the server switch immediately returns clients to safe read-only
  behavior without losing queued local work.

Exit criterion: no open P0/P1 and all evidence identifies account, budget,
record, mutation, and row-version scopes using opaque IDs only.

## Chunk 4 — Activation and observation

This chunk requires separate owner approval after Chunks 1–3 are green.

1. Enable `budget_data_safety_config.writes_enabled` for the controlled
   production environment.
2. Re-run the server RPC matrix before distributing an enabled client.
3. Build and install the exact reviewed client commit with the approved Gate C
   configuration.
4. Re-run the two-account smoke matrix from the installed app.
5. Observe authentication failures, RPC error classes, conflict counts,
   duplicate prevention, pending mutation count, and crashes without logging
   private financial content.

## Rollback

1. Set `writes_enabled = false` immediately.
2. Keep the client installed but fail closed/read-only; do not re-enable
   direct table writes.
3. Preserve local pending mutations, mutation receipts, tombstones, and the
   production database for diagnosis.
4. Revert the client activation configuration for the next build if needed.
5. Restore the pre-Gate-C database backup only for verified corruption that
   cannot be repaired forward, with separate owner authorization.

## Definition of done

- Migration `00300` is deployed and recorded.
- Gate C server writes are enabled only after the disabled-state postflight.
- The reviewed client configuration is enabled on an identified commit.
- Two-account authenticated QA passes before and after activation.
- Hosted migration, iOS Debug, iPhone/iPad UI, Release analyze/archive, and
  secret checks pass.
- Rollback-to-read-only is rehearsed and documented.
- Gate D deferred actions remain disabled.
