# Supabase database delivery

## Source roles

`supabase/migrations/` is the forward-only deployment path. Each future
behavioral database change belongs in a timestamped migration file and must be
applied in order through the Supabase migration workflow.

`supabase/budgetmate_schema.sql` is the cumulative schema snapshot and review
reference. It contains the accumulated desired contract and historical blocks;
it is not the deployment mechanism and must not be treated as a replacement for
an ordered migration chain.

The documentation in `docs/database-sync-hardening-2026-07.md` provides context
for the existing sync contract. It does not convert the cumulative snapshot
into a migration directory.

## Rules for database PRs

- PR 00A contains zero behavioral SQL migrations and performs no remote database
  operation.
- New database behavior is forward-only and belongs under
  `supabase/migrations/`.
- A PR contains at most one behavioral SQL migration. Split additional behavior
  into a separately reviewable PR.
- Use expand/migrate/contract. Do not drop legacy columns or remove compatibility
  paths while older released clients may still use them.
- Before writing a migration, read-only verification must confirm the target
  tables, columns, policies, functions, triggers, and extensions.
- Test the migration in local or staging environments, capture preflight and
  rollback evidence, and obtain explicit owner authorization before production
  apply or rollback.
- Updating `budgetmate_schema.sql` is documentation-only mechanical work; it does
  not authorize applying SQL.

## Local tooling and workspace hygiene

Supabase CLI metadata under `/supabase/.temp/` and
`/web/supabase/.temp/` is reproducible local state and is ignored. The
`web/supabase/` directory itself remains available for source or evidence and
must not be broadly ignored without classification.
