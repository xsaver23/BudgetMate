\set ON_ERROR_STOP on

do $$
begin
  if not exists (
       select 1
       from pg_proc function_record
       cross join lateral unnest(coalesce(function_record.proconfig, '{}'::text[])) setting
       where function_record.oid = 'public.mutate_budget_transaction(uuid,uuid,bigint,uuid,text,jsonb)'::regprocedure
         and setting = 'lock_timeout=750ms'
     ) then
    raise exception 'transaction RPC lock timeout is not bounded';
  end if;
  if not exists (
       select 1
       from pg_proc function_record
       cross join lateral unnest(coalesce(function_record.proconfig, '{}'::text[])) setting
       where function_record.oid = 'public.mutate_budget_settlement(uuid,uuid,bigint,uuid,text,jsonb)'::regprocedure
         and setting = 'lock_timeout=750ms'
     ) then
    raise exception 'settlement RPC lock timeout is not bounded';
  end if;
  if (select row_version from public.budget_transactions
      where id = '20000000-0000-0000-0000-000000000098') <> 1
     or (select amount from public.budget_transactions
         where id = '20000000-0000-0000-0000-000000000098') <> 7
     or (select row_version from public.budget_settlements
         where id = '40000000-0000-0000-0000-000000000098') <> 1
     or (select amount from public.budget_settlements
         where id = '40000000-0000-0000-0000-000000000098') <> 7 then
    raise exception 'bounded stale probes changed fixture rows';
  end if;
  if (select count(*) from public.budget_mutation_receipts
      where mutation_id in (
        'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaa0037',
        'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaa0038'
      )) <> 0 then
    raise exception 'bounded stale probes wrote receipts';
  end if;
end
$$;
