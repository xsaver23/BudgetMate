# Database and cross-client sync hardening — July 2026

The final block in `supabase/budgetmate_schema.sql` is an idempotent hardening
migration for the iOS/web shared contract. Run it from the Supabase SQL editor
as the project database owner. Do not deploy only the stricter policies without
the helper functions and triggers that precede them.

## High-severity causes found

1. Historical RLS policies remained live when newer household policies were
   added. PostgreSQL combines permissive policies with OR, so the old
   `auth.uid() = user_id` transaction/member/invite policies bypassed active
   membership checks and revocation.
2. iOS pushed its local snapshot before pulling, while both clients used blind
   upserts. Since `updated_at` had no update trigger and neither client supplied
   a precondition, a stale device could overwrite a newer edit. A stale local
   row could also recreate a remotely deleted UUID.
3. Every update payload replaced `user_id` with the signed-in writer. Updating a
   shared row could silently transfer creator ownership and alter later iOS push
   decisions.
4. Invite acceptance and shared-household creation were three/four separate HTTP
   writes. A network or RLS failure left partial state. An accepted invite also
   remained replayable after membership revocation.
5. `splits` accepted arbitrary JSON. iOS rejects/filters malformed values while
   web maps them differently, so a bad row could produce different totals and
   settlements.
6. Transaction and settlement business days were stored only as `timestamptz`.
   iOS writes a local DatePicker instant and web historically wrote local noon;
   the intended calendar day cannot be recovered reliably in another zone.

## Contract added

- `updated_at` is database-owned and advances on every insert/update.
- `row_version` is database-owned, starts at 1, and increments on update. It is
  ready for a later compare-and-swap RPC; ordinary payloads must omit it.
- `user_id`, `budget_id`, record ids, and creation timestamps are immutable on
  updates. `user_id` means original row creator, not last editor.
- `occurred_on date` is nullable on transactions and settlements. Updated
  clients dual-write exact `YYYY-MM-DD`, prefer it on reads, and fall back to
  legacy `date` until migration completes.
- Transaction/settlement deletes create scoped tombstones. Recreating a UUID
  clears its tombstone, matching the current last-write-wins behavior. Clients
  still use full scoped pulls for correctness. Whole-budget cascades skip child
  tombstones because the tombstone's parent budget is being removed too.
- Financial checks enforce positive cent transaction amounts, cent settlement
  amounts, distinct settlement parties, and valid split arrays for new/updated
  rows. They are `NOT VALID`, so legacy violations do not block deployment.
- Realtime uses `REPLICA IDENTITY FULL`; events are invalidation hints, not a
  substitute for a coalesced scoped fetch. Supabase Postgres Changes cannot
  filter DELETE events and, with RLS, exposes only their primary keys, so the
  web listener intentionally subscribes without a `budget_id` filter.
- `accept_budget_invite(p_invite_id uuid) -> uuid` atomically accepts an invite
  and returns its budget id.
- `create_budget_household(p_name text, p_budget_id uuid default null,
  p_owner_member_id uuid default null) -> uuid` atomically creates/repairs the
  budget, owner membership/profile, and settings row.
- Deleting a non-owner member profile now cancels its pending/accepted invite
  and removes its linked membership in the same database transaction. This
  keeps older two-request clients from leaving invisible active access behind.

## Preflight

Take a database backup, then run these read-only checks before the hardening
block. Review any returned rows; do not auto-rewrite creator ids or business
dates because the missing intent cannot be reconstructed safely.

```sql
-- Owner membership invariant.
select b.id, b.owner_user_id
from public.budgets b
left join public.budget_memberships m
  on m.budget_id = b.id
 and m.user_id = b.owner_user_id
 and m.role = 'owner'
 and m.status = 'active'
where m.user_id is null;

-- Case-insensitive invite duplicates / non-normalized addresses.
select budget_id, lower(btrim(email)) as normalized_email, count(*)
from public.budget_invites
group by budget_id, lower(btrim(email))
having count(*) > 1;

select id, budget_id, email
from public.budget_invites
where email <> lower(btrim(email)) or btrim(email) = '';

-- Rows that will remain readable but fail their next write until repaired.
select id, budget_id, amount, type, splits
from public.budget_transactions
where amount <= 0
   or amount <> round(amount, 2)
   or not public.valid_budget_transaction_splits(type, amount, splits);

select id, budget_id, amount, from_member_id, to_member_id
from public.budget_settlements
where amount <> round(amount, 2)
   or from_member_id = to_member_id;

-- Legacy business-date instants requiring a household-specific decision.
select budget_id,
       extract(hour from date at time zone 'UTC') as utc_hour,
       count(*)
from public.budget_transactions
group by budget_id, extract(hour from date at time zone 'UTC')
order by budget_id, utc_hour;
```

The split validator is created inside the hardening block, so run its preflight
query after applying the function but before validating the constraint, or copy
that function into a separate transaction first.

## Deployment order

1. Deploy the schema hardening block. Confirm functions, policies, triggers, and
   indexes exist. The new columns are optional to old clients.
2. Deploy iOS/web changes that stop clean snapshot upserts, serialize/coalesce
   refreshes, use Realtime only for invalidation, and dual-write `occurred_on`.
3. Switch invite acceptance and new-household creation to the atomic RPCs.
   Fall back only when PostgREST reports that the function is absent, never for
   authorization/conflict errors.
4. Run a two-user/two-client test: concurrent edit, remote delete, offline add,
   invite acceptance retry, pending-invite cancellation, owner revocation, and
   a transaction near midnight in two different time zones.
5. Repair legacy invalid rows, then validate staged constraints individually:

```sql
alter table public.budget_transactions
  validate constraint budget_transactions_positive_cent_amount;
alter table public.budget_transactions
  validate constraint budget_transactions_valid_splits;
alter table public.budget_settlements
  validate constraint budget_settlements_cent_amount;
alter table public.budget_settlements
  validate constraint budget_settlements_distinct_members;
alter table public.budget_invites
  validate constraint budget_invites_normalized_email;
```

6. After all supported clients dual-write `occurred_on`, backfill legacy rows
   using the household's confirmed intended day, make the column non-null, and
   stop using the legacy instant for grouping. Do not use `date::date` as a
   universal backfill.

## Residual risks

- Direct upserts remain last-write-wins. `row_version` does not prevent a dirty
  concurrent edit until mutation RPCs accept an expected version and reject a
  mismatch.
- Existing incorrectly transferred `user_id` values have no trustworthy
  automatic backfill. PostgreSQL/Audit logs or user review are required.
- Any active member can currently delete shared transactions/settlements,
  preserving the existing clear-all product behavior. Restrict those policies
  to creator-or-owner if that behavior is not intentional.
- Settings remain one JSON document per budget. Concurrent edits to different
  category keys can overwrite each other; per-key rows or a merge RPC would
  provide true collaborative editing.
- iOS clear-all currently sends the transaction delete and settlement delete
  as two requests. A failure between them leaves a partially cleared budget;
  move both deletes into one authorized database RPC before treating clear-all
  as atomic.
- Regular index creation can briefly lock a large production table. For a large
  dataset, create equivalent indexes `CONCURRENTLY` outside a transaction before
  running the rest of the block.
