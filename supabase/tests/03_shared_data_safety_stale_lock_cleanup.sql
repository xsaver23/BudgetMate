\set ON_ERROR_STOP on

begin;
update public.budget_data_safety_config
set writes_enabled = false
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
commit;
