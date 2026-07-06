# Performance & Sync Fixes — July 2026

Fixes for the iOS lag reported on iPhone 14 Pro, plus related sync-correctness
and web-app improvements. Both builds verified: iOS (`xcodebuild`, iPhone 16
simulator) and web (`npm run build`, includes TypeScript checks).

## Root cause of the lag

Every 20 seconds, the background sync loop rewrote **every transaction in the
local SwiftData store even when nothing had changed** — every field was
reassigned, and every split row was deleted and re-inserted. SwiftData marked
all of it dirty, saved it to disk, and invalidated every `@Query`-backed view,
so the dashboard and transaction list fully re-rendered every 20 seconds.
Each of those re-renders then re-ran expensive derivations several times per
render. On top of that, the sync merge was mutating the main-thread SwiftData
context from a background thread (undefined behavior that can itself cause
stutters and hangs).

## iOS fixes

### 1. Sync merge now diffs before writing (`SupabaseBudgetSyncService.swift`)
- Added `matches(...)` / `splitsMatch(...)` checks to the cloud row types.
  During merge, a transaction or settlement is only written when the cloud
  row actually differs from the local one; splits are only rebuilt when they
  differ. An idle sync cycle now performs **zero** SwiftData writes, so the
  UI no longer re-renders every 20 seconds.

### 2. SwiftData is no longer touched off the main thread
- `SupabaseBudgetSyncService` is now `@MainActor`. Previously it ran on a
  background executor after its first `await` while reading and mutating
  models from the main `ModelContext`, which is not thread-safe. Network
  calls still run asynchronously; only the model reads/writes are pinned to
  the main actor.

### 3. Fewer network round trips per sync cycle
- `ensurePersonalBudget` (2 upserts) and `repairMemberProfileIfNeeded`
  (1 update) now run once per app launch per user/budget scope instead of on
  every 20-second cycle.
- The sync summary now carries the cloud settings and members it already
  observed, and `BudgetMateApp` / `SettingsView` reuse them instead of
  issuing 3 extra fetches (settings + members + memberships) after every sync.
- Net effect: an idle sync cycle dropped from ~13 requests to ~8, and the
  remaining ones are lightweight reads.

### 4. Transactions tab no longer recomputes everything 3× per render
  (`TransactionsView.swift`, `SettlementComputationCache.swift`)
- Previously `summaryTotals`, `groupedByDay`, and the empty-state check each
  independently re-ran dedupe → recurring-transaction resolution → sort →
  filter on every SwiftUI body evaluation.
- Added `TransactionsTabMetrics`, computed once per actual data/filter change
  via a fingerprint-keyed `.task(id:)` — the same pattern DashboardView
  already used. Body evaluations now read cached values.

### 5. Offline data-loss protection (`needsSync` flag)
- New `needsSync` property on `Transaction` and `Settlement`, set when a row
  is created or edited locally and cleared once the sync merge confirms it in
  the cloud.
- Fixes this scenario: while offline, add an expense with "Paid By" set to
  your partner → the immediate cloud upsert fails → the next full sync
  declined to push it (payer isn't the signed-in member) and then **deleted
  it locally** because it wasn't in the cloud. Now:
  - the bulk push includes any locally created row not yet in the cloud, and
  - the prune pass never deletes rows still flagged `needsSync`.
- Existing rows migrate with `needsSync = false`, so nothing previously
  synced changes behavior (and remote deletes still propagate correctly).

### 6. Small cleanup
- `CloudSyncStore.statusText` no longer allocates a `RelativeDateTimeFormatter`
  on every call (now a cached static), matching the earlier formatter cleanups.

## Web fixes (`web/src/App.tsx`)
- Memoized the derived collections that previously recomputed on every
  render: `budgetMembers`, `budgetSettlements`, `displayedTransactions`,
  `totals`, `categoryTotals`, and `settlements` (settlement suggestions —
  the most expensive one) are now wrapped in `useMemo` with proper
  dependencies, alongside the already-memoized `budgetTransactions` and
  `monthTransactions`.

## Reviewed but deliberately not changed
- **Incremental pulls / Supabase Realtime**: pulls are still full-table per
  budget. Switching to `updated_at` watermarks would break remote-delete
  detection (the prune pass depends on the full pull) and needs schema
  changes plus tombstones. With the merge now diff-based, full pulls are far
  cheaper than before; revisit if budgets grow to thousands of rows.
- **Sync coalescing**: overlapping sync requests (scene-activation +
  20-second loop + pull-to-refresh) still queue behind each other rather
  than merging into one. Harmless but slightly wasteful; a shared in-flight
  task would fix it.
- **File splits**: `SupabaseBudgetSyncService.swift` (~1.7k lines) and
  `App.tsx` (~2.2k lines) would benefit from being split into modules;
  skipped to keep this change reviewable.

## Behavior notes for testing
- First sync after updating will rewrite each transaction once (local dates
  carry sub-second precision; cloud dates are second-precision, so the first
  diff "misses" and normalizes them). Every cycle after that is write-free.
- Sample-data seeding, member management, invites, and settle-up flows are
  unchanged.
