\set ON_ERROR_STOP on

begin;
set local statement_timeout = '2000ms';
set local role authenticated;
select set_config('request.jwt.claim.sub', '90000000-0000-0000-0000-000000000001', true);

do $$
declare
  started_at timestamptz := clock_timestamp();
  elapsed_ms numeric;
  error_code text;
  succeeded boolean := false;
begin
  begin
    perform public.mutate_budget_settlement(
      '10000000-0000-0000-0000-000000000001',
      '40000000-0000-0000-0000-000000000098',
      0,
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaa0038',
      'update',
      '{"from_member_id":"80000000-0000-0000-0000-000000000002","to_member_id":"80000000-0000-0000-0000-000000000001","amount":8}'::jsonb
    );
    succeeded := true;
  exception when others then
    get stacked diagnostics error_code = returned_sqlstate;
    elapsed_ms := extract(epoch from clock_timestamp() - started_at) * 1000;
    if error_code <> '55P03' or elapsed_ms > 1500 then
      raise exception 'settlement lock wait contract failed';
    end if;
  end;
  if succeeded then
    raise exception 'locked stale settlement unexpectedly succeeded';
  end if;
end
$$;
rollback;
