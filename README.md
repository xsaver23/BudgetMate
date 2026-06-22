# BudgetMate

BudgetMate is a personal and shared-household budgeting app for iOS and the web. It is built around a local-first budgeting experience with optional Supabase cloud sync, so a household can track spending, split expenses, manage category budgets, and settle up from either the mobile app or a desktop browser.

The project includes:

- A native SwiftUI iOS app.
- A React and TypeScript desktop web app.
- Shared Supabase schema and sync contracts used by both clients.

Live web app: [budgetmate.pages.dev](https://budgetmate.pages.dev)

## Features

- Email and password authentication with Supabase.
- Personal budgets and shared household budgets.
- Member-aware transaction tracking.
- Income, expense, category, date, payment method, and member metadata.
- Split expenses across household members.
- Settlement suggestions and balance breakdowns.
- Category budgets and monthly pacing.
- Recurring expenses with optional stop dates.
- Currency display preferences.
- Member filters for dashboard, transactions, and budget views.
- Local desktop mode for development and offline demos.
- Cloud sync between iOS and web using the same Supabase tables.

## Apps

### iOS

The iOS app is built with SwiftUI and uses local device storage for the primary app experience. Supabase is used for authentication, backup, and shared-budget collaboration.

Key areas:

- `BudgetMate/BudgetMateApp.swift` handles startup, auth routing, and sync bootstrapping.
- `BudgetMate/Services/CloudSyncStore.swift` exposes user-facing sync state and cloud actions.
- `BudgetMate/Services/SupabaseBudgetSyncService.swift` contains Supabase read/write logic.
- `BudgetMate/Views/Dashboard/DashboardView.swift` is the main dashboard.
- `BudgetMate/Views/Transactions/TransactionsView.swift` lists transactions.
- `BudgetMate/Views/Transactions/AddTransactionView.swift` creates transactions.
- `BudgetMate/Views/Budget/BudgetView.swift` manages monthly category budgets.
- `BudgetMate/Views/Settings/SettingsView.swift` manages account, household, sync, and data settings.

### Web

The web app is a Vite, React, and TypeScript companion app designed for desktop browsers on macOS and Windows.

Key areas:

- `web/src/App.tsx` contains the main app shell and views.
- `web/src/domain/` contains budgeting math, types, categories, formatting, and local domain logic.
- `web/src/data/cloudRepository.ts` maps web actions to the same Supabase tables used by iOS.
- `web/src/data/storage.ts` handles local browser storage and import/export.

## Tech Stack

- SwiftUI
- SwiftData/local iOS persistence
- React
- TypeScript
- Vite
- Supabase Auth
- Supabase Postgres
- Cloudflare Pages

## Data Model

BudgetMate uses shared Supabase tables so iOS and web can read and write the same budget data.

Core tables:

- `budgets`
- `budget_memberships`
- `budget_invites`
- `budget_members`
- `budget_settings`
- `budget_transactions`
- `budget_settlements`

Important distinction:

- `budget_memberships` controls access to a budget.
- `budget_members` stores the display/member rows shown in the app.

The full schema lives in:

```text
supabase/budgetmate_schema.sql
```

Additional architecture notes:

```text
docs/shared-budgets-architecture.md
```

## Local Setup

### iOS

1. Open `BudgetMate.xcodeproj` in Xcode.
2. Select an iOS Simulator or signed physical device.
3. Create `BudgetMate/Config/Supabase.local.xcconfig`.
4. Add the Supabase values:

```xcconfig
BUDGETMATE_SUPABASE_URL = https://your-project.supabase.co
BUDGETMATE_SUPABASE_PUBLISHABLE_KEY = your-publishable-key
```

The local config file should not be committed.

Build check:

```bash
xcodebuild -scheme BudgetMate -project BudgetMate.xcodeproj -destination 'generic/platform=iOS Simulator' build
```

### Web

Install dependencies and run the local dev server:

```bash
cd web
npm install
npm run dev
```

Open the Vite URL shown in the terminal, usually:

```text
http://localhost:5173/
```

Production build:

```bash
cd web
npm run build
npm run preview
```

## Web Cloud Sync

The web app supports two modes:

- Local mode: stores data in browser local storage and works without Supabase credentials.
- Cloud mode: signs in with Supabase and syncs with the same backend as the iOS app.

To enable cloud mode locally:

```bash
cd web
cp .env.example .env.local
```

Then set:

```text
VITE_SUPABASE_URL=https://your-project.supabase.co
VITE_SUPABASE_PUBLISHABLE_KEY=your-publishable-key
```

## Deployment

The web app is deployed as a static Vite app on Cloudflare Pages.

Cloudflare Pages settings:

```text
Framework preset: Vite
Root directory: web
Build command: npm run build
Build output directory: dist
```

Production environment variables:

```text
VITE_SUPABASE_URL=https://your-project.supabase.co
VITE_SUPABASE_PUBLISHABLE_KEY=your-publishable-key
```

## Product Principles

BudgetMate is designed to feel calm, clear, and practical:

- Lead with financial clarity.
- Keep sync and shared-budget state visible.
- Make shared money understandable.
- Use warmth with restraint.
- Prefer familiar controls over novelty.

More product notes are available in:

```text
PRODUCT.md
DESIGN.md
```
