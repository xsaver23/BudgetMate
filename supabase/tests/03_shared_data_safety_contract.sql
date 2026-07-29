\set ON_ERROR_STOP on

do $$
declare
  transaction_creator uuid;
  settlement_creator uuid;
  transaction_version bigint;
  settlement_version bigint;
  mutation_id uuid := 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaa0001';
  delete_mutation_id uuid := 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaa0002';
  settlement_delete_mutation_id uuid := 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaa0007';
  result jsonb;
  error_message text;
begin
  if public.budget_data_safety_enabled() then
    raise exception 'Gate C server writes must start disabled';
  end if;

  if (select created_by_user_id from public.budget_transactions
      where id = '20000000-0000-0000-0000-000000000001')
     <> '90000000-0000-0000-0000-000000000001'
     or (select created_by_user_id from public.budget_settlements
         where id = '40000000-0000-0000-0000-000000000001')
        <> '90000000-0000-0000-0000-000000000001' then
    raise exception 'Legacy creator identity was not attributed from the authenticated writer field';
  end if;

  if (select count(*) from pg_policies
      where schemaname = 'public'
        and tablename in ('budget_transactions', 'budget_settlements')
        and cmd in ('INSERT', 'UPDATE', 'DELETE')) <> 0 then
    raise exception 'Direct transaction/settlement write policies remain after Gate C';
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
    raise exception 'Authenticated RPC execute privileges are missing';
  end if;

  if not has_table_privilege('authenticated', 'public.budget_transactions', 'SELECT')
     or not has_table_privilege('authenticated', 'public.budget_settlements', 'SELECT')
     or has_table_privilege('authenticated', 'public.budget_transactions', 'INSERT')
     or has_table_privilege('authenticated', 'public.budget_transactions', 'UPDATE')
     or has_table_privilege('authenticated', 'public.budget_transactions', 'DELETE')
     or has_table_privilege('authenticated', 'public.budget_settlements', 'INSERT')
     or has_table_privilege('authenticated', 'public.budget_settlements', 'UPDATE')
     or has_table_privilege('authenticated', 'public.budget_settlements', 'DELETE') then
    raise exception 'Direct DML grant closure is incomplete';
  end if;

  perform set_config('request.jwt.claim.sub', '90000000-0000-0000-0000-000000000001', true);
  begin
    perform public.mutate_budget_transaction(
      '10000000-0000-0000-0000-000000000001',
      '20000000-0000-0000-0000-000000000099',
      0,
      mutation_id,
      'insert',
      '{"title":"blocked","amount":1,"type":"expense","category":"food","created_by_member_id":"80000000-0000-0000-0000-000000000001","splits":[]}'::jsonb
    );
    raise exception 'Disabled Gate C accepted a transaction mutation';
  exception
    when sqlstate '55000' then null;
  end;

  update public.budget_data_safety_config
  set writes_enabled = true
  where id = true;

  -- Exercise the direct-DML closure as the client role, not as the fixture
  -- owner that runs this contract.
  set local role authenticated;
  begin
    insert into public.budget_transactions (
      id, user_id, budget_id, title, amount, type, category,
      created_by_member_id, date, created_at, splits
    ) values (
      '20000000-0000-0000-0000-000000000097',
      '90000000-0000-0000-0000-000000000001',
      '10000000-0000-0000-0000-000000000001',
      'direct', 1, 'expense', 'food',
      '80000000-0000-0000-0000-000000000001', now(), now(), '[]'::jsonb
    );
    raise exception 'Authenticated direct transaction INSERT was accepted';
  exception when insufficient_privilege then null;
  end;
  begin
    update public.budget_transactions set amount = amount + 1
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
    update public.budget_settlements set amount = amount + 1
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
  reset role;

  result := public.mutate_budget_transaction(
    '10000000-0000-0000-0000-000000000001',
    '20000000-0000-0000-0000-000000000099',
    0,
    mutation_id,
    'insert',
    '{"title":"Gate C insert","amount":1,"type":"expense","category":"food","created_by_member_id":"80000000-0000-0000-0000-000000000001","splits":[]}'::jsonb
  );
  select created_by_user_id, row_version
  into transaction_creator, transaction_version
  from public.budget_transactions
  where id = '20000000-0000-0000-0000-000000000099';
  if transaction_creator <> '90000000-0000-0000-0000-000000000001'
     or transaction_version <> 1
     or result ->> 'replayed' <> 'false' then
    raise exception 'Transaction RPC did not establish authoritative creator/version state';
  end if;

  result := public.mutate_budget_transaction(
    '10000000-0000-0000-0000-000000000001',
    '20000000-0000-0000-0000-000000000099',
    0,
    mutation_id,
    'insert',
    '{"title":"Gate C insert","amount":1,"type":"expense","category":"food","created_by_member_id":"80000000-0000-0000-0000-000000000001","splits":[]}'::jsonb
  );
  if result ->> 'replayed' <> 'true'
     or (select amount from public.budget_transactions where id = '20000000-0000-0000-0000-000000000099') <> 1 then
    raise exception 'Transaction mutation replay was not idempotent';
  end if;

  begin
    perform public.mutate_budget_transaction(
      '10000000-0000-0000-0000-000000000001',
      '20000000-0000-0000-0000-000000000099',
      0,
      mutation_id,
      'insert',
      '{"title":"different","amount":99,"type":"expense","category":"food","created_by_member_id":"80000000-0000-0000-0000-000000000001","splits":[]}'::jsonb
    );
    raise exception 'Different payload was accepted for an existing transaction mutation id';
  exception
    when sqlstate 'P0001' then
      get stacked diagnostics error_message = message_text;
      if error_message <> 'idempotency_mismatch' then raise; end if;
  end;

  -- Every member-shaped reference is scoped to an active profile in the
  -- target household, including split participants.
  begin
    perform public.mutate_budget_transaction(
      '10000000-0000-0000-0000-000000000001',
      '20000000-0000-0000-0000-000000000096',
      0,
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaa0010',
      'insert',
      '{"title":"cross-household","amount":1,"type":"expense","category":"food","created_by_member_id":"80000000-0000-0000-0000-000000000003","splits":[]}'::jsonb
    );
    raise exception 'Cross-household creator reference was accepted';
  exception when sqlstate '42501' then null;
  end;
  begin
    perform public.mutate_budget_transaction(
      '10000000-0000-0000-0000-000000000001',
      '20000000-0000-0000-0000-000000000095',
      0,
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaa0011',
      'insert',
      '{"title":"cross-split","amount":1,"type":"expense","category":"food","created_by_member_id":"80000000-0000-0000-0000-000000000001","splits":[{"id":"81000000-0000-0000-0000-000000000001","member_id":"80000000-0000-0000-0000-000000000003","amount":1}]}'::jsonb
    );
    raise exception 'Cross-household split reference was accepted';
  exception when sqlstate '42501' then null;
  end;
  insert into public.budget_members (id, user_id, budget_id, auth_user_id, invite_status)
  values (
    '80000000-0000-0000-0000-000000000004',
    '90000000-0000-0000-0000-000000000002',
    '10000000-0000-0000-0000-000000000001',
    '90000000-0000-0000-0000-000000000002',
    'removed'
  );
  begin
    perform public.mutate_budget_transaction(
      '10000000-0000-0000-0000-000000000001',
      '20000000-0000-0000-0000-000000000094',
      0,
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaa0012',
      'insert',
      '{"title":"removed","amount":1,"type":"expense","category":"food","created_by_member_id":"80000000-0000-0000-0000-000000000004","splits":[]}'::jsonb
    );
    raise exception 'Removed member reference was accepted';
  exception when sqlstate '42501' then null;
  end;

  perform public.mutate_budget_transaction(
    '10000000-0000-0000-0000-000000000001',
    '20000000-0000-0000-0000-000000000099',
    1,
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaa0003',
    'update',
    '{"title":"updated","amount":2,"type":"expense","category":"food","created_by_member_id":"80000000-0000-0000-0000-000000000001","splits":[]}'::jsonb
  );
  if (select row_version from public.budget_transactions
      where id = '20000000-0000-0000-0000-000000000099') <> 2 then
    raise exception 'Transaction CAS update did not advance the row version';
  end if;

  begin
    perform public.mutate_budget_transaction(
      '10000000-0000-0000-0000-000000000001',
      '20000000-0000-0000-0000-000000000099',
      1,
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaa0004',
      'update',
      '{"title":"stale","amount":3,"type":"expense","category":"food","created_by_member_id":"80000000-0000-0000-0000-000000000001","splits":[]}'::jsonb
    );
    raise exception 'Stale transaction CAS update was accepted';
  exception
    when sqlstate '40001' then null;
  end;

  insert into public.budget_memberships (budget_id, user_id, role, status)
  values ('10000000-0000-0000-0000-000000000001', '90000000-0000-0000-0000-000000000002', 'member', 'active');
  perform set_config('request.jwt.claim.sub', '90000000-0000-0000-0000-000000000002', true);
  begin
    perform public.mutate_budget_transaction(
      '10000000-0000-0000-0000-000000000001',
      '20000000-0000-0000-0000-000000000099',
      2,
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaa0005',
      'update',
      '{"title":"member overwrite","amount":4,"type":"expense","category":"food","created_by_member_id":"80000000-0000-0000-0000-000000000001","splits":[]}'::jsonb
    );
    raise exception 'Non-creator member mutation was accepted';
  exception
    when sqlstate '42501' then null;
  end;

  perform set_config('request.jwt.claim.sub', '90000000-0000-0000-0000-000000000001', true);
  result := public.mutate_budget_transaction(
    '10000000-0000-0000-0000-000000000001',
    '20000000-0000-0000-0000-000000000099',
    2,
    delete_mutation_id,
    'delete',
    '{}'::jsonb
  );
  if result ->> 'deleted' <> 'true'
     or (select deleted_by_mutation_id::text from public.budget_sync_tombstones
         where entity_type = 'transaction'
           and budget_id = '10000000-0000-0000-0000-000000000001'
           and record_id = '20000000-0000-0000-0000-000000000099')
        <> delete_mutation_id::text then
    raise exception 'Transaction deletion did not leave a durable mutation tombstone';
  end if;

  result := public.mutate_budget_transaction(
    '10000000-0000-0000-0000-000000000001',
    '20000000-0000-0000-0000-000000000099',
    2,
    delete_mutation_id,
    'delete',
    '{}'::jsonb
  );
  if result ->> 'replayed' <> 'true' then
    raise exception 'Transaction deletion replay was not idempotent';
  end if;

  begin
    perform public.mutate_budget_transaction(
      '10000000-0000-0000-0000-000000000001',
      '20000000-0000-0000-0000-000000000099',
      2,
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaa0013',
      'update',
      '{"title":"resurrect","amount":1,"type":"expense","category":"food","created_by_member_id":"80000000-0000-0000-0000-000000000001","splits":[]}'::jsonb
    );
    raise exception 'Transaction update resurrected a tombstoned record';
  exception
    when sqlstate 'P0002' then
      get stacked diagnostics error_message = message_text;
      if error_message <> 'remote_deleted' then raise; end if;
  end;
  begin
    perform public.mutate_budget_transaction(
      '10000000-0000-0000-0000-000000000001',
      '20000000-0000-0000-0000-000000000099',
      2,
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaa0022',
      'delete',
      '{}'::jsonb
    );
    raise exception 'Transaction delete did not report remote deletion';
  exception
    when sqlstate 'P0002' then
      get stacked diagnostics error_message = message_text;
      if error_message <> 'remote_deleted' then raise; end if;
  end;
  begin
    perform public.mutate_budget_transaction(
      '10000000-0000-0000-0000-000000000001',
      '20000000-0000-0000-0000-000000000099',
      0,
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaa0014',
      'insert',
      '{"title":"resurrect","amount":1,"type":"expense","category":"food","created_by_member_id":"80000000-0000-0000-0000-000000000001","splits":[]}'::jsonb
    );
    raise exception 'Transaction insert resurrected a tombstoned record';
  exception
    when sqlstate 'P0002' then
      get stacked diagnostics error_message = message_text;
      if error_message <> 'remote_deleted' then raise; end if;
  end;
  begin
    perform public.mutate_budget_transaction(
      '10000000-0000-0000-0000-000000000001',
      '20000000-0000-0000-0000-000000000093',
      1,
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaa0015',
      'update',
      '{}'::jsonb
    );
    raise exception 'Never-existing transaction did not fail';
  exception
    when sqlstate 'P0002' then
      get stacked diagnostics error_message = message_text;
      if error_message <> 'record_not_found' then raise; end if;
  end;

  result := public.mutate_budget_settlement(
    '10000000-0000-0000-0000-000000000001',
    '40000000-0000-0000-0000-000000000099',
    0,
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaa0006',
    'insert',
    '{"from_member_id":"80000000-0000-0000-0000-000000000002","to_member_id":"80000000-0000-0000-0000-000000000001","amount":1}'::jsonb
  );
  select created_by_user_id, row_version
  into settlement_creator, settlement_version
  from public.budget_settlements
  where id = '40000000-0000-0000-0000-000000000099';
  if settlement_creator <> '90000000-0000-0000-0000-000000000001'
     or settlement_version <> 1
     or result ->> 'replayed' <> 'false' then
    raise exception 'Settlement RPC did not establish authoritative creator/version state';
  end if;

  begin
    perform public.mutate_budget_settlement(
      '10000000-0000-0000-0000-000000000001',
      '40000000-0000-0000-0000-000000000096',
      0,
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaa0018',
      'insert',
      '{"from_member_id":"80000000-0000-0000-0000-000000000003","to_member_id":"80000000-0000-0000-0000-000000000001","amount":1}'::jsonb
    );
    raise exception 'Cross-household settlement reference was accepted';
  exception when sqlstate '42501' then null;
  end;
  begin
    perform public.mutate_budget_settlement(
      '10000000-0000-0000-0000-000000000001',
      '40000000-0000-0000-0000-000000000095',
      0,
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaa0019',
      'insert',
      '{"from_member_id":"80000000-0000-0000-0000-000000000001","to_member_id":"80000000-0000-0000-0000-000000000001","amount":1}'::jsonb
    );
    raise exception 'Self-settlement reference was accepted';
  exception when sqlstate '22023' then null;
  end;

  perform public.mutate_budget_settlement(
    '10000000-0000-0000-0000-000000000001',
    '40000000-0000-0000-0000-000000000099',
    1,
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaa0008',
    'update',
    '{"from_member_id":"80000000-0000-0000-0000-000000000002","to_member_id":"80000000-0000-0000-0000-000000000001","amount":2}'::jsonb
  );
  if (select row_version from public.budget_settlements
      where id = '40000000-0000-0000-0000-000000000099') <> 2 then
    raise exception 'Settlement CAS update did not advance the row version';
  end if;

  begin
    perform public.mutate_budget_settlement(
      '10000000-0000-0000-0000-000000000001',
      '40000000-0000-0000-0000-000000000099',
      1,
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaa0009',
      'update',
      '{"amount":3}'::jsonb
    );
    raise exception 'Stale settlement CAS update was accepted';
  exception
    when sqlstate '40001' then null;
  end;

  result := public.mutate_budget_settlement(
    '10000000-0000-0000-0000-000000000001',
    '40000000-0000-0000-0000-000000000099',
    2,
    settlement_delete_mutation_id,
    'delete',
    '{}'::jsonb
  );
  if result ->> 'deleted' <> 'true'
     or (select deleted_by_mutation_id::text from public.budget_sync_tombstones
         where entity_type = 'settlement'
           and budget_id = '10000000-0000-0000-0000-000000000001'
           and record_id = '40000000-0000-0000-0000-000000000099')
        <> settlement_delete_mutation_id::text then
    raise exception 'Settlement deletion did not leave a durable mutation tombstone';
  end if;

  result := public.mutate_budget_settlement(
    '10000000-0000-0000-0000-000000000001',
    '40000000-0000-0000-0000-000000000099',
    2,
    settlement_delete_mutation_id,
    'delete',
    '{}'::jsonb
  );
  if result ->> 'replayed' <> 'true' then
    raise exception 'Settlement deletion replay was not idempotent';
  end if;

  begin
    perform public.mutate_budget_settlement(
      '10000000-0000-0000-0000-000000000001',
      '40000000-0000-0000-0000-000000000099',
      2,
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaa0016',
      'update',
      '{"from_member_id":"80000000-0000-0000-0000-000000000002","to_member_id":"80000000-0000-0000-0000-000000000001","amount":3}'::jsonb
    );
    raise exception 'Settlement update resurrected a tombstoned record';
  exception
    when sqlstate 'P0002' then
      get stacked diagnostics error_message = message_text;
      if error_message <> 'remote_deleted' then raise; end if;
  end;
  begin
    perform public.mutate_budget_settlement(
      '10000000-0000-0000-0000-000000000001',
      '40000000-0000-0000-0000-000000000099',
      0,
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaa0017',
      'insert',
      '{"from_member_id":"80000000-0000-0000-0000-000000000002","to_member_id":"80000000-0000-0000-0000-000000000001","amount":3}'::jsonb
    );
    raise exception 'Settlement insert resurrected a tombstoned record';
  exception
    when sqlstate 'P0002' then
      get stacked diagnostics error_message = message_text;
      if error_message <> 'remote_deleted' then raise; end if;
  end;
  begin
    perform public.mutate_budget_settlement(
      '10000000-0000-0000-0000-000000000001',
      '40000000-0000-0000-0000-000000000099',
      2,
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaa0023',
      'delete',
      '{}'::jsonb
    );
    raise exception 'Settlement delete did not report remote deletion';
  exception
    when sqlstate 'P0002' then
      get stacked diagnostics error_message = message_text;
      if error_message <> 'remote_deleted' then raise; end if;
  end;
end
$$;

-- The rehearsal must not leave the gate enabled for a subsequent job step.
update public.budget_data_safety_config
set writes_enabled = false
where id = true;
