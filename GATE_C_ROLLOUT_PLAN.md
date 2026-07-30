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
- The linked project has pre-00300 `last_mutation_id` columns plus an
  unledgered legacy mutation surface. The pending migration must retire that
  surface before production application; the older 00300 text is not an
  acceptable production candidate.
- The Gate C server configuration does not exist in production yet.
- iOS `MoneyServerBridgeRollout` and `SharedDataSafetyGate` default to
  disabled.
- The production web client still shares the same Supabase backend and is a
  required Gate C participant. Ordinary web builds default to read-only for
  financial writes.
- Gate D keeps unfinished invitation, leave, ownership-transfer, clear-all,
  and account-deletion actions unavailable.

## Scope guardrails

- No new product feature, UI redesign, schema redesign, or unrelated cleanup.
- One forward server migration: the already-merged `00300`.
- The corrected 00300 may remove only the six identified legacy CAS RPCs, their
  obsolete mutation-ID/tombstone helpers and triggers, and the three identified
  unmatched transaction/settlement write policies. It must preserve authorized
  reads and the 00400 trigger contract.
- No destructive down migration and no production restore unless a verified
  incident requires the pre-rollout backup.
- This repository does not claim that a production backup exists. Before any
  production apply, the owner must approve creation of an access-restricted,
  encrypted logical backup and a restore/fingerprint rehearsal. Do not enable
  PITR or change a billing/plan setting as part of this code chunk.
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
   signatures, and the exact pre-00300 legacy drift. Confirm the corrected
   migration retires all six authenticated legacy CAS RPCs, the obsolete
   mutation-ID/tombstone helper-trigger surface, and the three unmatched write
   policies while preserving reads and 00400.
2. With owner approval, create a secure logical production backup, record an
   opaque checksum and restricted storage location, and restore it into an
   isolated PostgreSQL rehearsal. A dry-run or an unverified CLI export is not
   a rollback backup.
3. Rehearse applying `00300` after already-applied `00400`. Supabase requires
   an explicit `--include-all` because `00300` sorts before the latest remote
   migration.
4. Prove migration replay/idempotency, PostgreSQL contract tests,
   concurrency tests, old-client read behavior, and rollback restore.
5. Dry-run the exact production command and prove it selects only `00300`.
6. With separate owner approval, deploy `00300` while
   `writes_enabled = false`.
7. Postflight must prove:
   - Gate C reports disabled.
   - Existing authorized reads still work.
   - Direct transaction and settlement writes are denied.
   - Gate C RPC writes fail closed with the documented disabled error.
   - Migration `00400` trigger permissions remain correct.

Exit criterion: production has `00300`, the write switch is false, and all
disabled-state checks pass.

## Chunk 2 — Fail-closed iOS and web activation

Owner: Gate C client tracks.

1. Replace hard-coded rollout decisions with one explicit, testable
   configuration contract per client.
2. Default every ordinary iOS Debug/Release build and web deployment to
   disabled.
3. Require money-bridge compatibility and Gate C activation together; any
   missing or inconsistent value fails closed.
4. Route iOS and web financial writes only through the two Gate C RPCs when
   enabled; no direct financial-table DML fallback is allowed.
5. Persist pending mutations before network or optimistic UI work. Verify the
   exact RPC request and stable mutation ID survive offline failure, browser or
   app relaunch, and authenticated replay, and remain user/budget scoped while
   disabled.
6. Cover insert, update, delete, retry, conflict mapping, capability rules,
   account/budget switching, and accessible read-only messaging.
7. Run focused tests, full iOS unit/UI suites, iPhone/iPad builds, web tests
   and production builds in disabled and all-enabled configurations, Release
   analyze/archive, secret scan, and project-integrity checks.

Exit criterion: a reviewed candidate can be explicitly enabled without
changing source again, while default iOS and web builds remain disabled.

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
3. Build and install the exact reviewed iOS commit and deploy the exact
   reviewed web commit with their approved Gate C configurations.
4. Re-run the two-account smoke matrix from both clients.
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
- The reviewed iOS and web configurations are enabled on an identified
  commit.
- Two-account authenticated QA passes before and after activation.
- Hosted migration, iOS Debug, iPhone/iPad UI, Release analyze/archive, and
  web test/build, Cloudflare, and secret checks pass.
- Rollback-to-read-only is rehearsed and documented.
- Gate D deferred actions remain disabled.
