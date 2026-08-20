begin;
-- The harness deliberately owns the Result lock. The business RPC below runs
-- with a real authenticated GM JWT context and must serialize on this Result.
select id from public.race_results
where horse_id = '00000000-0000-0000-0000-00000000fa30'
  and status = 'CONFIRMED'::public.race_result_status
for update;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000fa03', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select pg_sleep(3);
select id from public.correct_race_result(
  (select id from public.race_results where horse_id = '00000000-0000-0000-0000-00000000fa30' and status = 'CONFIRMED'::public.race_result_status),
  (select id from public.actual_races where race_catalog_id = '00000000-0000-0000-0000-00000000fa40'),
  1::smallint, 3000000::bigint, null, null, null, 'concurrent prize correction'
);
commit;
