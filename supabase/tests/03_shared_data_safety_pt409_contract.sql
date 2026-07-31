\set ON_ERROR_STOP on

-- Local PostgreSQL contract for the hosted PostgREST error shape. The
-- authenticated role exercises the same security-definer RPC entry point;
-- exact message text remains stable for the iOS/web message-based mappers.
begin;

update public.budget_data_safety_config
set writes_enabled = true
where id = true;

set local role authenticated;
select set_config('request.jwt.claim.sub', '90000000-0000-0000-0000-000000000001', true);

do $contract$
declare
  transaction_record constant uuid := '20000000-0000-0000-0000-000000000086';
  settlement_record constant uuid := '40000000-0000-0000-0000-000000000086';
  transaction_insert_mutation constant uuid := 'cccccccc-cccc-4ccc-8ccc-cccccccc0086';
  settlement_insert_mutation constant uuid := 'cccccccc-cccc-4ccc-8ccc-cccccccc0087';
  transaction_stale_mutation constant uuid := 'cccccccc-cccc-4ccc-8ccc-cccccccc0088';
  settlement_stale_mutation constant uuid := 'cccccccc-cccc-4ccc-8ccc-cccccccc0089';
  transaction_invalid_insert_mutation constant uuid := 'cccccccc-cccc-4ccc-8ccc-cccccccc0090';
  settlement_invalid_insert_mutation constant uuid := 'cccccccc-cccc-4ccc-8ccc-cccccccc0091';
  actual_state text;
  actual_message text;
begin
  perform public.mutate_budget_transaction(
    '10000000-0000-0000-0000-000000000001', transaction_record, 0,
    transaction_insert_mutation, 'insert',
    '{"title":"PT409 transaction","amount":11,"type":"expense","category":"food","created_by_member_id":"80000000-0000-0000-0000-000000000001","splits":[]}'::jsonb
  );

  begin
    perform public.mutate_budget_transaction(
      '10000000-0000-0000-0000-000000000001', transaction_record, 0,
      transaction_stale_mutation, 'update',
      '{"title":"must not apply","amount":99,"type":"expense","category":"food","created_by_member_id":"80000000-0000-0000-0000-000000000001","splits":[]}'::jsonb
    );
    raise exception 'Stale transaction update was accepted';
  exception
    when sqlstate 'PT409' then
      get stacked diagnostics
        actual_state = returned_sqlstate,
        actual_message = message_text;
      if actual_state <> 'PT409'
         or actual_message <> 'The transaction changed on another device.' then
        raise exception 'Unexpected transaction conflict contract';
      end if;
  end;

  begin
    perform public.mutate_budget_transaction(
      '10000000-0000-0000-0000-000000000001',
      '20000000-0000-0000-0000-000000000087', 7,
      transaction_invalid_insert_mutation, 'insert',
      '{"title":"must not insert","amount":12,"type":"expense","category":"food","created_by_member_id":"80000000-0000-0000-0000-000000000001","splits":[]}'::jsonb
    );
    raise exception 'Nonzero-version transaction insert was accepted';
  exception
    when sqlstate 'PT409' then
      get stacked diagnostics
        actual_state = returned_sqlstate,
        actual_message = message_text;
      if actual_state <> 'PT409'
         or actual_message <> 'An insert must use row version zero.' then
        raise exception 'Unexpected transaction insert-version contract';
      end if;
  end;

  perform public.mutate_budget_settlement(
    '10000000-0000-0000-0000-000000000001', settlement_record, 0,
    settlement_insert_mutation, 'insert',
    '{"from_member_id":"80000000-0000-0000-0000-000000000002","to_member_id":"80000000-0000-0000-0000-000000000001","amount":13}'::jsonb
  );

  begin
    perform public.mutate_budget_settlement(
      '10000000-0000-0000-0000-000000000001', settlement_record, 0,
      settlement_stale_mutation, 'update',
      '{"amount":99}'::jsonb
    );
    raise exception 'Stale settlement update was accepted';
  exception
    when sqlstate 'PT409' then
      get stacked diagnostics
        actual_state = returned_sqlstate,
        actual_message = message_text;
      if actual_state <> 'PT409'
         or actual_message <> 'The settlement changed on another device.' then
        raise exception 'Unexpected settlement conflict contract';
      end if;
  end;

  begin
    perform public.mutate_budget_settlement(
      '10000000-0000-0000-0000-000000000001',
      '40000000-0000-0000-0000-000000000087', 7,
      settlement_invalid_insert_mutation, 'insert',
      '{"from_member_id":"80000000-0000-0000-0000-000000000002","to_member_id":"80000000-0000-0000-0000-000000000001","amount":14}'::jsonb
    );
    raise exception 'Nonzero-version settlement insert was accepted';
  exception
    when sqlstate 'PT409' then
      get stacked diagnostics
        actual_state = returned_sqlstate,
        actual_message = message_text;
      if actual_state <> 'PT409'
         or actual_message <> 'An insert must use row version zero.' then
        raise exception 'Unexpected settlement insert-version contract';
      end if;
  end;
end
$contract$;

reset role;

do $verification$
declare
  transaction_oid oid := 'public.mutate_budget_transaction(uuid,uuid,bigint,uuid,text,jsonb)'::regprocedure::oid;
  settlement_oid oid := 'public.mutate_budget_settlement(uuid,uuid,bigint,uuid,text,jsonb)'::regprocedure::oid;
  transaction_definition text;
  settlement_definition text;
begin
  select pg_get_functiondef(transaction_oid), pg_get_functiondef(settlement_oid)
    into transaction_definition, settlement_definition;
  if regexp_count(transaction_definition, $$errcode = 'PT409'$$) <> 2
     or regexp_count(settlement_definition, $$errcode = 'PT409'$$) <> 2
     or regexp_count(transaction_definition, $$errcode = '40001'$$) <> 0
     or regexp_count(settlement_definition, $$errcode = '40001'$$) <> 0 then
    raise exception 'Gate C RPC conflict SQLSTATE replacement is incomplete';
  end if;

  if not (select prosecdef from pg_proc where oid = transaction_oid)
     or not (select prosecdef from pg_proc where oid = settlement_oid) then
    raise exception 'Gate C RPC security-definer contract changed';
  end if;
  if not exists (
       select 1 from pg_proc p
       cross join lateral unnest(coalesce(p.proconfig, '{}'::text[])) setting
       where p.oid = transaction_oid
         and setting = 'search_path=pg_catalog, public, auth'
     )
     or not exists (
       select 1 from pg_proc p
       cross join lateral unnest(coalesce(p.proconfig, '{}'::text[])) setting
       where p.oid = settlement_oid
         and setting = 'search_path=pg_catalog, public, auth'
     )
     or not exists (
       select 1 from pg_proc p
       cross join lateral unnest(coalesce(p.proconfig, '{}'::text[])) setting
       where p.oid = transaction_oid
         and setting = 'lock_timeout=750ms'
     )
     or not exists (
       select 1 from pg_proc p
       cross join lateral unnest(coalesce(p.proconfig, '{}'::text[])) setting
       where p.oid = settlement_oid
         and setting = 'lock_timeout=750ms'
     ) then
    raise exception 'Gate C RPC function configuration changed';
  end if;
  if not has_function_privilege(
       'authenticated',
       'public.mutate_budget_transaction(uuid,uuid,bigint,uuid,text,jsonb)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'authenticated',
       'public.mutate_budget_settlement(uuid,uuid,bigint,uuid,text,jsonb)',
       'EXECUTE'
     ) then
    raise exception 'Gate C RPC execute grants changed';
  end if;

  if (select amount from public.budget_transactions
      where id = '20000000-0000-0000-0000-000000000086') <> 11
     or (select row_version from public.budget_transactions
         where id = '20000000-0000-0000-0000-000000000086') <> 1
     or (select amount from public.budget_settlements
         where id = '40000000-0000-0000-0000-000000000086') <> 13
     or (select row_version from public.budget_settlements
         where id = '40000000-0000-0000-0000-000000000086') <> 1 then
    raise exception 'Stale PT409 probes changed their target rows';
  end if;
  if exists (
       select 1 from public.budget_transactions
       where id = '20000000-0000-0000-0000-000000000087'
     )
     or exists (
       select 1 from public.budget_settlements
       where id = '40000000-0000-0000-0000-000000000087'
     ) then
    raise exception 'Invalid-version PT409 probes inserted rows';
  end if;
  if (select count(*) from public.budget_mutation_receipts
      where mutation_id in (
        'cccccccc-cccc-4ccc-8ccc-cccccccc0088',
        'cccccccc-cccc-4ccc-8ccc-cccccccc0089',
        'cccccccc-cccc-4ccc-8ccc-cccccccc0090',
        'cccccccc-cccc-4ccc-8ccc-cccccccc0091'
      )) <> 0 then
    raise exception 'Conflict probes wrote mutation receipts';
  end if;
end
$verification$;

-- All fixture mutations and the temporary gate enablement are discarded.
rollback;
