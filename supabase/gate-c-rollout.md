# Gate C server rollout

`20260729000300_shared_data_safety.sql` is intentionally disabled by default:
it inserts `budget_data_safety_config.writes_enabled = false`. It also removes
client-role direct transaction and settlement writes, so it must not be applied
until the intended controlled-beta client has the Gate C RPC contract and its
distribution/enable sequence is ready.

## Operational write window

Applying `00300` immediately revokes direct DML, even though the RPC gate stays
disabled. From the migration commit until a separate, owner-approved
`writes_enabled = true` change, **all transaction and settlement mutations are
read-only**: legacy clients lose direct writes and Gate C clients receive the
disabled-gate RPC response. This is an intentional safety hold, not a
backwards-compatible grace period.

Keep the window short and planned: prepare and review the exact RPC-capable
build first, but do not install or distribute a configuration that attempts
Gate C writes until the migration and its disabled postflight are verified.
Take the backup and dry-run evidence immediately before the maintenance window,
apply `00300` only when the rollout owner is available to observe it, and
schedule the separate enable decision at the end of the controlled-beta
rehearsal. Do not apply `00300` during a period when normal transaction or
settlement entry must remain available.

Production has recorded `00100`, `00200`, and `00400`, with `00300` pending.
Because `00300` sorts before the already-recorded `00400`, the linked-project
preflight and apply commands require `--include-all`.

## Read-only rehearsal

From the repository root, with the intended linked Supabase project selected:

```bash
bash scripts/rehearse_gate_c_production_migration.sh
```

The script runs only `supabase migration list --linked` and
`supabase db push --linked --include-all --dry-run`; it has no apply mode.
Capture its output with the change record. Confirm it plans only
`20260729000300_shared_data_safety.sql`, and that the recorded history still
contains `00400`.

Before the maintenance window, run this read-only SQL-editor preflight and
capture the result. It checks the tables required by `00300`, including the
sync tombstone table that the migration alters but does not create, and rejects
an unexpected pre-existing enabled gate:

```sql
do $$
begin
  if to_regclass('public.budgets') is null
     or to_regclass('public.budget_memberships') is null
     or to_regclass('public.budget_members') is null
     or to_regclass('public.budget_transactions') is null
     or to_regclass('public.budget_settlements') is null
     or to_regclass('public.budget_sync_tombstones') is null then
    raise exception 'Gate C prerequisite table is missing';
  end if;

  if to_regclass('public.budget_data_safety_config') is not null then
    if exists (
      select 1
      from public.budget_data_safety_config
      where id = true and writes_enabled
    ) then
      raise exception 'Refusing a disabled-by-default rollout over an enabled Gate C configuration';
    end if;
  end if;
end
$$;
```

## Authorized deployment and verification

Only after the rollout owner has approved a fresh backup and the client
compatibility check, an operator may apply the pending migration:

```bash
supabase db push --linked --include-all
```

Immediately verify the migration history and the disabled state in the
Supabase SQL editor:

```sql
select version, name
from supabase_migrations.schema_migrations
where version in ('20260729000100', '20260729000200', '20260729000300', '20260729000400')
order by version;

select writes_enabled
from public.budget_data_safety_config
where id = true;
```

The required result is a recorded `00300` and `writes_enabled = false`. Do not
change that flag during this deployment. Rehearse the RPCs and controlled beta
while disabled; a separate owner-approved change is required to enable writes.

Shared-household beta validation needs two already-active members. Gate D
invitations are disabled, so use an existing two-member household or have a
privileged database operator provision the test membership through the approved
staging/production change process. Do not attempt to create that membership
through the disabled invitation flow during the rollout.

## Rollback boundary

There is no down migration. If the migration must be reversed, stop the
rollout, preserve the incident evidence, and restore the verified pre-`00300`
backup under the database owner’s change process. That backup must include
`00100`, `00200`, and `00400`; restoring the older pre-money-bridge snapshot
would also discard unrelated deployed work. After restore, verify `00300` is
absent, `budget_data_safety_config` is absent, and the `00400` trigger
permission contract still holds.
