-- Gate C: make optimistic-version conflicts PostgREST-compatible.
--
-- PostgreSQL class 40 errors are transaction-rollback errors. PostgREST can
-- hold those responses until its transaction handling completes, which makes
-- a stale RPC look like a network hang. PT409 is a custom SQLSTATE in the
-- supported application-error class and maps to an HTTP 409 response without
-- changing the mutation contract. This migration changes only the four
-- version-conflict raises in the two 00300 RPC definitions.
--
-- The guarded catalog rewrite keeps the 00300 function bodies in one place,
-- rejects unexpected drift, and is safe to replay after the conversion.

begin;

do $migration$
declare
  target_oid oid;
  function_definition text;
  legacy_conflict_count integer;
  converted_conflict_count integer;
begin
  for target_oid in
    select unnest(array[
      'public.mutate_budget_transaction(uuid,uuid,bigint,uuid,text,jsonb)'::regprocedure::oid,
      'public.mutate_budget_settlement(uuid,uuid,bigint,uuid,text,jsonb)'::regprocedure::oid
    ])
  loop
    select pg_get_functiondef(target_oid)
      into function_definition;

    legacy_conflict_count := regexp_count(
      function_definition,
      $$errcode = '40001'$$
    );
    converted_conflict_count := regexp_count(
      function_definition,
      $$errcode = 'PT409'$$
    );

    if legacy_conflict_count = 2 and converted_conflict_count = 0 then
      function_definition := replace(
        function_definition,
        $$errcode = '40001'$$,
        $$errcode = 'PT409'$$
      );
    elsif legacy_conflict_count = 0 and converted_conflict_count = 2 then
      -- Idempotent replay: the exact expected replacement is already present.
      null;
    else
      raise exception
        'Unexpected optimistic-conflict definition drift for % (legacy %, converted %)',
        target_oid::regprocedure,
        legacy_conflict_count,
        converted_conflict_count;
    end if;

    execute function_definition;
  end loop;
end
$migration$;

-- Reassert the security boundary and the 00500 lock bound after replacement.
alter function public.mutate_budget_transaction(uuid, uuid, bigint, uuid, text, jsonb)
  security definer;
alter function public.mutate_budget_transaction(uuid, uuid, bigint, uuid, text, jsonb)
  set search_path = pg_catalog, public, auth;
alter function public.mutate_budget_transaction(uuid, uuid, bigint, uuid, text, jsonb)
  set lock_timeout = '750ms';
alter function public.mutate_budget_settlement(uuid, uuid, bigint, uuid, text, jsonb)
  security definer;
alter function public.mutate_budget_settlement(uuid, uuid, bigint, uuid, text, jsonb)
  set search_path = pg_catalog, public, auth;
alter function public.mutate_budget_settlement(uuid, uuid, bigint, uuid, text, jsonb)
  set lock_timeout = '750ms';

revoke all on function public.mutate_budget_transaction(uuid, uuid, bigint, uuid, text, jsonb) from public;
revoke all on function public.mutate_budget_settlement(uuid, uuid, bigint, uuid, text, jsonb) from public;
grant execute on function public.mutate_budget_transaction(uuid, uuid, bigint, uuid, text, jsonb) to authenticated;
grant execute on function public.mutate_budget_settlement(uuid, uuid, bigint, uuid, text, jsonb) to authenticated;

notify pgrst, 'reload schema';

commit;
