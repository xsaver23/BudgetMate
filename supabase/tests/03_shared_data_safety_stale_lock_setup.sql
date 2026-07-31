\set ON_ERROR_STOP on

update public.budget_data_safety_config
set writes_enabled = true
where id = true;

delete from public.budget_mutation_receipts
where mutation_id in (
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaa0035',
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaa0036',
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaa0037',
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaa0038'
);
delete from public.budget_transactions
where id = '20000000-0000-0000-0000-000000000098';
delete from public.budget_settlements
where id = '40000000-0000-0000-0000-000000000098';
delete from public.budget_sync_tombstones
where record_id in (
  '20000000-0000-0000-0000-000000000098',
  '40000000-0000-0000-0000-000000000098'
);

begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', '90000000-0000-0000-0000-000000000001', true);

select public.mutate_budget_transaction(
  '10000000-0000-0000-0000-000000000001',
  '20000000-0000-0000-0000-000000000098',
  0,
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaa0035',
  'insert',
  '{"title":"stale lock fixture","amount":7,"type":"expense","category":"food","created_by_member_id":"80000000-0000-0000-0000-000000000001","splits":[]}'::jsonb
);
select public.mutate_budget_settlement(
  '10000000-0000-0000-0000-000000000001',
  '40000000-0000-0000-0000-000000000098',
  0,
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaa0036',
  'insert',
  '{"from_member_id":"80000000-0000-0000-0000-000000000002","to_member_id":"80000000-0000-0000-0000-000000000001","amount":7}'::jsonb
);
commit;
