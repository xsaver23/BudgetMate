# BudgetMate Web

React/TypeScript desktop web companion for BudgetMate.

## Run

```bash
npm install
npm run dev
```

Open the Vite URL, usually:

```text
http://localhost:5173/
```

## Build

```bash
npm run build
npm run preview
```

## Deploy To Cloudflare Pages

BudgetMate Web is a static Vite app, so Cloudflare Pages can host it directly.

Use these Pages settings:

```text
Framework preset: Vite
Root directory: web
Build command: npm run build
Build output directory: dist
```

Add these production environment variables in Cloudflare Pages:

```text
VITE_SUPABASE_URL=https://your-project.supabase.co
VITE_SUPABASE_PUBLISHABLE_KEY=your-publishable-key
```

You can also deploy from the CLI after signing in to Cloudflare:

```bash
npx wrangler pages deploy dist --project-name budgetmate
```

## Data Modes

The web app has two modes.

Desktop-local mode stores data in browser local storage and works without a backend.

Cloud mode uses Supabase email/password auth and the same tables as the SwiftUI app. Add `.env.local` to enable cloud mode:

```bash
cp .env.example .env.local
```

```text
VITE_SUPABASE_URL=https://your-project.supabase.co
VITE_SUPABASE_PUBLISHABLE_KEY=your-publishable-key
```

The app includes:

- Dashboard totals, pacing, category overview, recent activity, and settle-up suggestions.
- Transaction list, search, add, delete, member filter, and split-with-household transaction entry.
- Category budget editing and member spending.
- Settings for currency, members, household budgets, pending invites, data export, data import, and reset.
- Supabase sign-in, sign-up, refresh, sign out, shared budget creation, member invite creation, and invite acceptance.

Cloud writes are implemented in `src/data/cloudRepository.ts` and match the iOS app's Supabase contract:

- `budgets`
- `budget_memberships`
- `budget_settings`
- `budget_members`
- `budget_transactions`
- `budget_settlements`
- `budget_invites`

Desktop-local mode is still useful for demos, offline testing, and development without Supabase credentials.
