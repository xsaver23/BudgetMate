# BudgetMate

BudgetMate is a SwiftUI iOS budgeting app for personal and shared household budgeting. It is local-first, uses SwiftData for on-device storage, and syncs to Supabase for authentication, backup, and shared-budget collaboration.

Current snapshot: `223b97e`

This repo now also includes a React/TypeScript web companion in `web/` that runs in desktop browsers on macOS and Windows. The web app supports desktop-local browser storage and Supabase email/password sign-in for shared backend sync.

## What It Does

- Email/password authentication through Supabase.
- First-run profile setup and editable profile names.
- Personal budgets and named shared household budgets.
- Invite flow for creating a new household or adding someone to an owned household.
- Member-aware transactions with per-member filtering.
- Split expenses, settlement suggestions, and balance breakdowns.
- Category budgets with custom category emoji and monthly pacing.
- Recurring expenses with optional stop dates.
- Currency display selection.
- Light, dark, and system appearance options.
- Manual sync, auto sync, and pull-to-refresh on main pages.

## App Structure

- `BudgetMate/BudgetMateApp.swift` handles app startup, auth/profile flow, and sync bootstrapping.
- `BudgetMate/Services/CloudSyncStore.swift` exposes user-facing sync state and cloud actions.
- `BudgetMate/Services/SupabaseBudgetSyncService.swift` contains Supabase read/write logic.
- `BudgetMate/Views/Dashboard/DashboardView.swift` is the home dashboard.
- `BudgetMate/Views/Transactions/TransactionsView.swift` lists transactions.
- `BudgetMate/Views/Transactions/AddTransactionView.swift` adds and edits transactions.
- `BudgetMate/Views/Budget/BudgetView.swift` manages category budgets.
- `BudgetMate/Views/Settings/SettingsView.swift` manages account, household, sync, and app settings.
- `BudgetMate/Views/Settings/BudgetMembersView.swift` manages shared-budget members.
- `BudgetMate/Views/Settings/InviteMemberView.swift` creates or targets shared households for invites.
- `supabase/budgetmate_schema.sql` contains the Supabase schema and migrations.
- `docs/shared-budgets-architecture.md` documents the shared household architecture.
- `web/` contains the React/TypeScript desktop web app.
- `web/src/data/cloudRepository.ts` maps the web app to the same Supabase tables used by the iOS sync service.

## Local Setup

1. Open `BudgetMate.xcodeproj` in Xcode.
2. Use an iOS Simulator or a signed physical device target.
3. Add a local Supabase config file at `BudgetMate/Config/Supabase.local.xcconfig`.
4. Provide these build settings:

```xcconfig
BUDGETMATE_SUPABASE_URL = https://your-project.supabase.co
BUDGETMATE_SUPABASE_PUBLISHABLE_KEY = your-publishable-key
```

The local Supabase config should stay out of source control. The app expects those values through the bundle info dictionary at runtime.

## Supabase Setup

Run the SQL in `supabase/budgetmate_schema.sql` against the Supabase project. The app currently uses these tables:

- `budgets`
- `budget_memberships`
- `budget_invites`
- `budget_members`
- `budget_settings`
- `budget_transactions`
- `budget_settlements`

Important model distinction:

- `budget_memberships` grants access to a budget.
- `budget_members` stores the display/profile row shown in the app.

## Build Check

Use this simulator build command from the repo root:

```bash
xcodebuild -scheme BudgetMate -project '/Users/developer/BudgetMate/BudgetMate.xcodeproj' -destination 'generic/platform=iOS Simulator' build
```

## Web App

The web app can be run on any desktop computer with Node.js installed.

```bash
cd '/Users/developer/BudgetMate/web'
npm install
npm run dev
```

Open the local URL shown by Vite, usually:

```text
http://localhost:5173/
```

Production build and local preview:

```bash
cd '/Users/developer/BudgetMate/web'
npm run build
npm run preview
```

Supabase config for cloud sync in the web app:

```bash
cp .env.example .env.local
```

Then set:

```text
VITE_SUPABASE_URL=https://your-project.supabase.co
VITE_SUPABASE_PUBLISHABLE_KEY=your-publishable-key
```

Without `.env.local`, the web app runs in desktop-local mode. With `.env.local`, it starts at the Supabase sign-in screen and can:

- Sign in or create an email/password account.
- Load active budget memberships and budget names.
- Read and write shared settings, members, transactions, settlements, and invites.
- Create shared household budgets.
- Invite members by email.
- Accept pending invites for the signed-in email.
- Refresh cloud data and sign out.

The web app uses the same `budget_id`, `user_id`, `auth_user_id`, JSON `splits`, and per-budget `budget_settings` contract as the iOS app.

## Backups

Local backups are stored outside the repo at:

```text
/Users/developer/BudgetMate Backups/
```

Most recent backup created during this README update:

```text
/Users/developer/BudgetMate Backups/BudgetMate-backup-20260622-004246
```
