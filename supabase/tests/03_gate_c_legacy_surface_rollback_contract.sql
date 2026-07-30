\set ON_ERROR_STOP on

-- The restore rehearsal must return to the exact pre-00300 drift boundary:
-- legacy mutation objects are present, Gate C objects are absent, and the
-- 00400 money-bridge trigger contract can still be checked separately.
do $$
begin
  if to_regclass('public.budget_data_safety_config') is not null
     or to_regclass('public.budget_mutation_receipts') is not null
     or to_regprocedure('public.budget_data_safety_enabled()') is not null
     or to_regprocedure(
          'public.mutate_budget_transaction(uuid,uuid,bigint,uuid,text,jsonb)'
        ) is not null
     or to_regprocedure(
          'public.mutate_budget_settlement(uuid,uuid,bigint,uuid,text,jsonb)'
        ) is not null then
    raise exception 'Rollback restore contains Gate C objects';
  end if;

  if exists (
       select 1
       from information_schema.columns
       where table_schema = 'public'
         and table_name in ('budget_transactions', 'budget_settlements')
         and column_name = 'created_by_user_id'
     )
     or exists (
       select 1
       from information_schema.columns
       where table_schema = 'public'
         and table_name = 'budget_sync_tombstones'
         and column_name = 'deleted_by_mutation_id'
     ) then
    raise exception 'Rollback restore contains Gate C-only columns';
  end if;

  if (select count(*)
      from information_schema.columns
      where table_schema = 'public'
        and table_name in ('budget_transactions', 'budget_settlements')
        and column_name = 'last_mutation_id') <> 2 then
    raise exception 'Rollback restore lost the pre-existing mutation-ID columns';
  end if;

  if (select count(*)
      from (values
        (to_regprocedure('public.save_budget_transaction_cas(jsonb,bigint,uuid)')),
        (to_regprocedure('public.save_budget_settlement_cas(jsonb,bigint,uuid)')),
        (to_regprocedure('public.save_budget_transactions_cas(jsonb)')),
        (to_regprocedure('public.save_budget_settlements_cas(jsonb)')),
        (to_regprocedure('public.delete_budget_transaction_cas(uuid,uuid,bigint)')),
        (to_regprocedure('public.delete_budget_settlement_cas(uuid,uuid,bigint)'))
      ) as legacy_functions(regprocedure)
      where regprocedure is not null) <> 6 then
    raise exception 'Rollback restore did not restore all six legacy RPCs';
  end if;

  if (select count(*)
      from pg_trigger
      where tgname in (
        'b_clear_reused_transaction_mutation_id',
        'b_clear_reused_settlement_mutation_id',
        'z_capture_budget_transaction_delete',
        'z_capture_budget_settlement_delete',
        'z_clear_budget_transaction_tombstone',
        'z_clear_budget_settlement_tombstone'
      )
        and not tgisinternal) <> 6 then
    raise exception 'Rollback restore did not restore all legacy triggers';
  end if;

  if (select count(*)
      from pg_policies
      where schemaname = 'public'
        and tablename in ('budget_transactions', 'budget_settlements')
        and policyname in (
          'Active members can create owned transactions',
          'Active members can update transactions',
          'Creators and owners can delete transactions',
          'Active members can create owned settlements',
          'Creators and owners can update settlements',
          'Creators and owners can delete settlements'
        )) <> 6 then
    raise exception 'Rollback restore did not restore the legacy write policies';
  end if;

  if (select count(*)
      from (values
        ('public.save_budget_transaction_cas(jsonb,bigint,uuid)'),
        ('public.save_budget_settlement_cas(jsonb,bigint,uuid)'),
        ('public.save_budget_transactions_cas(jsonb)'),
        ('public.save_budget_settlements_cas(jsonb)'),
        ('public.delete_budget_transaction_cas(uuid,uuid,bigint)'),
        ('public.delete_budget_settlement_cas(uuid,uuid,bigint)')
      ) as legacy_grants(signature)
      where has_function_privilege('authenticated', signature, 'EXECUTE')) <> 6 then
    raise exception 'Rollback restore did not restore legacy authenticated grants';
  end if;
end
$$;
