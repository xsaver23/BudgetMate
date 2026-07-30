\set ON_ERROR_STOP on

-- Disabled-state postflight for the exact production-order rehearsal. Run this
-- immediately after 00300 and its idempotent replay, before the positive CAS
-- contract temporarily enables the local fixture gate.
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', '90000000-0000-0000-0000-000000000001', true);

do $$
declare
  transaction_count integer;
  settlement_count integer;
  cross_budget_transaction_count integer;
  error_message text;
begin
  if public.budget_data_safety_enabled() then
    raise exception 'Gate C server writes are not disabled';
  end if;

  select count(*) into transaction_count
  from public.budget_transactions
  where budget_id = '10000000-0000-0000-0000-000000000001';
  select count(*) into settlement_count
  from public.budget_settlements
  where budget_id = '10000000-0000-0000-0000-000000000001';
  select count(*) into cross_budget_transaction_count
  from public.budget_transactions
  where budget_id = '10000000-0000-0000-0000-000000000002';
  if transaction_count = 0
     or settlement_count = 0
     or cross_budget_transaction_count <> 0 then
    raise exception 'Authorized disabled-state reads are not household scoped';
  end if;

  if has_table_privilege('authenticated', 'public.budget_transactions', 'INSERT')
     or has_table_privilege('authenticated', 'public.budget_transactions', 'UPDATE')
     or has_table_privilege('authenticated', 'public.budget_transactions', 'DELETE')
     or has_table_privilege('authenticated', 'public.budget_settlements', 'INSERT')
     or has_table_privilege('authenticated', 'public.budget_settlements', 'UPDATE')
     or has_table_privilege('authenticated', 'public.budget_settlements', 'DELETE') then
    raise exception 'Authenticated direct DML grants remain while disabled';
  end if;

  if exists (
       select 1
       from pg_policies
       where schemaname = 'public'
         and tablename in ('budget_transactions', 'budget_settlements')
         and cmd in ('INSERT', 'UPDATE', 'DELETE')
     ) then
    raise exception 'Authenticated direct write policies remain while disabled';
  end if;

  if (select count(*)
      from (values
        (to_regprocedure('public.save_budget_transaction_cas(jsonb,bigint,uuid)')),
        (to_regprocedure('public.save_budget_settlement_cas(jsonb,bigint,uuid)')),
        (to_regprocedure('public.save_budget_transactions_cas(jsonb)')),
        (to_regprocedure('public.save_budget_settlements_cas(jsonb)')),
        (to_regprocedure('public.delete_budget_transaction_cas(uuid,uuid,bigint)')),
        (to_regprocedure('public.delete_budget_settlement_cas(uuid,uuid,bigint)')),
        (to_regprocedure('public.clear_reused_financial_mutation_id()')),
        (to_regprocedure('public.capture_budget_data_tombstone()')),
        (to_regprocedure('public.clear_budget_data_tombstone()'))
      ) as retired_objects(regprocedure)
      where regprocedure is not null) <> 0 then
    raise exception 'Legacy authenticated mutation surface remains callable';
  end if;

  begin
    perform public.mutate_budget_transaction(
      '10000000-0000-0000-0000-000000000001',
      '20000000-0000-0000-0000-000000000097',
      0,
      'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbb0001',
      'insert',
      '{"title":"disabled","amount":1,"type":"expense","category":"food","created_by_member_id":"80000000-0000-0000-0000-000000000001","splits":[]}'::jsonb
    );
    raise exception 'Disabled Gate C accepted a transaction mutation';
  exception
    when sqlstate '55000' then
      get stacked diagnostics error_message = message_text;
      if error_message <> 'Shared-data safety writes are not enabled.' then
        raise;
      end if;
  end;

  begin
    perform public.mutate_budget_settlement(
      '10000000-0000-0000-0000-000000000001',
      '40000000-0000-0000-0000-000000000097',
      0,
      'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbb0002',
      'insert',
      '{"from_member_id":"80000000-0000-0000-0000-000000000002","to_member_id":"80000000-0000-0000-0000-000000000001","amount":1}'::jsonb
    );
    raise exception 'Disabled Gate C accepted a settlement mutation';
  exception
    when sqlstate '55000' then
      get stacked diagnostics error_message = message_text;
      if error_message <> 'Shared-data safety writes are not enabled.' then
        raise;
      end if;
  end;

  begin
    insert into public.budget_transactions (
      id, user_id, budget_id, title, amount, type, category,
      created_by_member_id, date, created_at, splits
    ) values (
      '20000000-0000-0000-0000-000000000097',
      '90000000-0000-0000-0000-000000000001',
      '10000000-0000-0000-0000-000000000001',
      'disabled direct insert', 1, 'expense', 'food',
      '80000000-0000-0000-0000-000000000001', now(), now(), '[]'::jsonb
    );
    raise exception 'Authenticated direct transaction INSERT was accepted';
  exception when insufficient_privilege then null;
  end;

  begin
    update public.budget_transactions
    set amount = amount + 1
    where id = '20000000-0000-0000-0000-000000000001';
    raise exception 'Authenticated direct transaction UPDATE was accepted';
  exception when insufficient_privilege then null;
  end;

  begin
    delete from public.budget_transactions
    where id = '20000000-0000-0000-0000-000000000001';
    raise exception 'Authenticated direct transaction DELETE was accepted';
  exception when insufficient_privilege then null;
  end;

  begin
    insert into public.budget_settlements (
      id, user_id, budget_id, from_member_id, to_member_id, amount, date
    ) values (
      '40000000-0000-0000-0000-000000000097',
      '90000000-0000-0000-0000-000000000001',
      '10000000-0000-0000-0000-000000000001',
      '80000000-0000-0000-0000-000000000001',
      '80000000-0000-0000-0000-000000000002', 1, now()
    );
    raise exception 'Authenticated direct settlement INSERT was accepted';
  exception when insufficient_privilege then null;
  end;

  begin
    update public.budget_settlements
    set amount = amount + 1
    where id = '40000000-0000-0000-0000-000000000001';
    raise exception 'Authenticated direct settlement UPDATE was accepted';
  exception when insufficient_privilege then null;
  end;

  begin
    delete from public.budget_settlements
    where id = '40000000-0000-0000-0000-000000000001';
    raise exception 'Authenticated direct settlement DELETE was accepted';
  exception when insufficient_privilege then null;
  end;
end
$$;

rollback;
