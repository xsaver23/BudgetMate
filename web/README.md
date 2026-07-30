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

## Gate C financial-write rollout

Cloud transaction and settlement writes use the server-owned CAS/idempotency
RPCs (`mutate_budget_transaction` and `mutate_budget_settlement`); the web
client does not use direct DML for these tables. The RPC payload includes the
last read `row_version`. Before any network activity, the browser persists the
exact RPC request (including its generated mutation UUID) in a user-scoped
local outbox. It replays requests serially after reload, reconnect, or sign-in
and removes an entry only after a normal or idempotent replay receipt. The
outbox contains no authentication material.

The default build is intentionally read-only for cloud transactions and
settlements. It stays that way unless all three Cloudflare/Vite build variables
are explicitly `YES`:

```text
VITE_BUDGETMATE_GATE_C_SERVER_READY=YES
VITE_BUDGETMATE_GATE_C_ENABLED=YES
VITE_BUDGETMATE_MONEY_SERVER_BRIDGE_ENABLED=YES
```

Absent, malformed, or partially enabled markers fail closed and show an
in-product explanation. Do not set any marker in production until the Gate C
migration has been applied, the disabled postflight is verified, the RPC
contract has been rehearsed, and the rollout owner approves the write-enable
step. Web is a required controlled-beta participant, not an optional legacy
client.
