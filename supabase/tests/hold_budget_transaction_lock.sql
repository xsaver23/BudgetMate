\set ON_ERROR_STOP on

begin;
select id
from public.budget_transactions
where id = '20000000-0000-0000-0000-000000000098'
for update;
select pg_sleep(2);
commit;
