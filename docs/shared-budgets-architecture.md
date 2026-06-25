# Shared Budgets / Households — Architecture & Implementation Plan

Status: proposed
Owner: BudgetMate
Last updated: 2026-06-21

## 1. Goal

Let a user belong to multiple **budgets ("households")**:

- **My Budget** — private, one per user, `budgets.id == user_id`.
- **Zero or more shared budgets** — each its own UUID, named, with its own members,
  transactions, settlements, and settings.

When inviting someone, the owner can **create a new household (with a name)** or
**add the invitee to an existing household they own**. The Settings scope picker
lists every budget the user belongs to, by name.

## 2. Current state & problems

The data model already supports multiple budgets (`budgets`, `budget_memberships`,
and a `budget_id` column on every data table). Three things prevent it from working:

1. **No shared budget is ever created.** `createInvite` calls `ensurePersonalBudget`
   and targets the invite at the **personal** budget (`budget_id == user_id`). So an
   invitee is added to *My Budget*; there is only ever one budget. This is why the
   scope picker shows a single entry even with two members.
   - `SupabaseBudgetSyncService.createInvite(...)`
   - `ensurePersonalBudget(userId:)` → `budgets.id = userId`, name "My Budget".

2. **Settings are keyed per-user, not per-budget.** `budget_settings` PK is `user_id`
   and `upsertSettings` uses `onConflict: "user_id"` **and** early-returns unless
   `budgetId == userId`. A user therefore can only ever have one settings row, and
   shared-budget settings are never written. Per-household category budgets/emoji/
   currency are impossible without a schema change.

3. **Budget names are never surfaced.** `BudgetMembership.displayName(currentUserId:)`
   is hardcoded to `"My Budget"` / `"Shared Budget"`; the real `budgets.name` is not
   fetched. Multiple households would all read "Shared Budget".

Also note the sync push gate: `SupabaseBudgetSyncService.sync(...)` only pushes
**settings and members** when `budgetId == userId`. Shared budgets currently would
not sync settings/members.

## 3. Target architecture

### Entities (unchanged tables, two schema tweaks)

- `budgets(id, owner_user_id, name, ...)`
- `budget_memberships(budget_id, user_id, role, status)` — PK `(budget_id,user_id)`
- `budget_members(id, user_id, budget_id, auth_user_id, display_name, email, ...)`
- `budget_transactions / budget_settlements (..., budget_id)`
- `budget_settings(budget_id PK, owner_user_id, monthly_budget, currency_code, appearance, category_budgets, category_emojis, ...)` — **PK changes from `user_id` to `budget_id`**
- `budget_invites(id, budget_id, invited_by_user_id, display_name, email, status, ...)` — unique `(budget_id,email)`

### Scoping rules

- `currentUserScopeId` = auth user id (unchanged).
- `currentBudgetScopeId` = `activeBudgetScopeId ?? currentUserScopeId`.
- Personal budget id **==** user id (invariant kept).
- Shared budget id **!=** user id (a fresh UUID).
- All reads/writes scope by `budget_id == currentBudgetScopeId`.

## 4. Schema changes (SQL you run in Supabase)

### 4.1 `budget_settings` becomes per-budget

```sql
-- Each budget has exactly one settings row.
alter table public.budget_settings
  add column if not exists owner_user_id uuid references auth.users(id) on delete set null;

update public.budget_settings set owner_user_id = user_id where owner_user_id is null;

-- Drop the user-id primary key, key on budget_id instead.
-- (confirm constraint name first: \d budget_settings)
alter table public.budget_settings drop constraint if exists budget_settings_pkey;
update public.budget_settings set budget_id = user_id where budget_id is null;
-- guard against accidental dupes before adding the PK
-- (there should be at most one row per budget_id today)
alter table public.budget_settings add primary key (budget_id);
```

RLS for settings already supports member reads (`Budget members can read shared
settings`). Add member insert/update for shared settings:

```sql
drop policy if exists "Budget members can write shared settings" on public.budget_settings;
create policy "Budget members can write shared settings"
on public.budget_settings
for all
to authenticated
using (
  exists (select 1 from public.budget_memberships m
          where m.budget_id = budget_settings.budget_id
            and m.user_id = auth.uid() and m.status = 'active')
)
with check (
  exists (select 1 from public.budget_memberships m
          where m.budget_id = budget_settings.budget_id
            and m.user_id = auth.uid() and m.status = 'active')
);
```

### 4.2 Invite-to-owned hardening (optional but recommended)

Tighten `budget_invites` insert so the inviter must own (or belong to) the target
budget, not just set `invited_by_user_id` to themselves:

```sql
drop policy if exists "Owners can create budget invites" on public.budget_invites;
create policy "Owners can create budget invites"
on public.budget_invites
for insert
to authenticated
with check (
  invited_by_user_id = auth.uid()
  and exists (select 1 from public.budget_memberships m
              where m.budget_id = budget_invites.budget_id
                and m.user_id = auth.uid()
                and m.role = 'owner' and m.status = 'active')
);
```

No new tables are required.

## 5. One-time migration of the current state (Option A — keep history shared)

Today the existing shared data lives under `budget_id == <ownerUserId>` with the
owner plus another household member. We promote that into a new named Shared Budget
and leave *My Budget* private.

Approach (finalized against real rows before running):

1. `new_shared := gen_random_uuid()`; insert `budgets(new_shared, owner=<ownerUserId>, name='Shared Budget')`.
2. Insert owner membership `(new_shared, <ownerUserId>, owner, active)`.
3. Move the **other** member's membership: `update budget_memberships set budget_id=new_shared where budget_id=<ownerUserId> and user_id<>ownerUserId`.
4. Move shared data: `budget_transactions`, `budget_settlements`, `budget_invites`,
   and the **settings** row from `budget_id=<ownerUserId>` → `new_shared`.
5. `budget_members`: move the other household member's row to `new_shared`; for the
   owner, create a member row in `new_shared` (the shared profile) while keeping the
   private `My Budget` member row.
6. Insert a fresh default `budget_settings` row for `budget_id=<ownerUserId>` (empty My Budget).

> The member-row handling in step 5 is the delicate part (the owner's member id may
> equal the owner user id in personal scope). Query the actual rows and finalize this
> SQL before running it, so a shared profile is not stranded.

## 6. Sync layer (`SupabaseBudgetSyncService`)

- **`ensureSharedBudget(ownerUserId:name:) -> UUID`** (new): reuse an owned non-personal
  budget if one matches, else insert `budgets` (new UUID) + owner membership; return id.
- **`createInvite(displayName:email:budgetId:userScopeId:)`**: add explicit `budgetId`
  (no longer defaults to personal). Validate the caller owns `budgetId`.
- **`fetchMemberships(userScopeId:)`**: embed budget names —
  `.select("budget_id,user_id,role,status,budgets(name)")` — and map onto memberships.
- **`fetchOwnedBudgets(userScopeId:) -> [(id,name)]`** (new) for the invite "existing" list.
- **`upsertSettings` / `fetchSettings`**: key on `budget_id` (`onConflict: "budget_id"`),
  remove the `guard budgetId == userId` early return.
- **`sync(...)`**: replace the `budgetId == userId` gate on settings/members push so the
  active budget (shared or personal) syncs its settings and members.

## 7. Models & state

- `BudgetMembership` gains `name: String?`; `displayName(currentUserId:)` returns
  "My Budget" for the personal id, otherwise `name ?? "Shared Budget"`.
- `CloudBudgetMembershipRow` decodes the embedded `budgets(name)`.
- `AuthSessionStore.switchBudgetScope(to:)` already persists per-user; call it after a
  successful invite-create so the owner lands in the new household.
- `BudgetMateApp.selectSharedBudgetIfNeeded` stays, but should not override an
  explicit user selection; keep My Budget selectable.
- `CloudSyncStore`: thin async wrappers for `ensureSharedBudget`, `fetchOwnedBudgets`,
  and `createInvite(budgetId:)`.

## 8. UI

- **`InviteMemberView`**: add a household selector —
  - segmented/menu: "Create new household" (name field) vs "Add to existing" (menu of
    owned budgets by name);
  - then invitee name + email (existing, with emoji validation already in place).
- **`SettingsView`** scope picker: already lists memberships; now shows real names and
  supports >2 entries. Add a "New household" affordance if desired.

## 9. Edge cases & risks

- **Settings PK migration** is the riskiest DB step — confirm the constraint name and
  that there are no duplicate `budget_id` rows before adding the new PK.
- **Member-row identity** in the one-time migration (section 5, step 5).
- **`budgetId == userId` gates** appear for settings, members, and in `upsertSettings`;
  all must be updated together or shared budgets silently won't sync.
- **RLS recursion**: keep the existing non-recursive membership/budget read policies;
  add only the settings write + invite-owner policies above.
- **Solo users**: no shared budget exists until the first invite; behavior unchanged.
- **Leaving / deleting**: `leaveBudget` and `deleteAllBudgetData` already key off an
  explicit `budgetId` / `budgetId != userId`; verify they operate on the active shared id.

## 10. Sequencing

1. **Phase 1 — plumbing (no behavior change):** budget-name fetch + `BudgetMembership.name`;
   settings keyed by `budget_id` (+ SQL 4.1); remove the `budgetId == userId` sync gates.
2. **Phase 2 — create/choose household:** `ensureSharedBudget`, `createInvite(budgetId:)`,
   `fetchOwnedBudgets`, revised `InviteMemberView`, switch scope after invite.
3. **Phase 3 — one-time migration** (section 5) for existing shared household data.
4. **Phase 4 — verify** (section 11).

## 11. Test plan

- Solo user: only "My Budget" in picker; no shared budget created.
- Invite → create new "Home": new budget UUID appears; owner switches into it; invitee
  accepts and sees it; data scoped to the new id; My Budget stays private/empty.
- Invite → add to existing household: no new budget; invitee joins the chosen one.
- Per-household settings: category budgets/emoji differ between My Budget and a shared
  budget and sync independently across both devices.
- Clear-all in a shared budget removes both members' rows (existing fix) and prunes on
  the other device.
- Two-device run across an owner device and member device, with console output captured.
```
