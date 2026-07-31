begin;

-- 00300's update/delete path must lock the current row before evaluating its
-- version. A long-lived concurrent writer could otherwise leave a stale RPC
-- waiting until the PostgREST/client timeout. Bound only the RPC lock wait;
-- the timeout aborts before any financial write or receipt is committed, so a
-- caller can safely retry the same mutation id after the conflicting writer
-- finishes. This does not enable the Gate C server gate.
alter function public.mutate_budget_transaction(uuid, uuid, bigint, uuid, text, jsonb)
  set lock_timeout = '750ms';
alter function public.mutate_budget_settlement(uuid, uuid, bigint, uuid, text, jsonb)
  set lock_timeout = '750ms';

notify pgrst, 'reload schema';

commit;
