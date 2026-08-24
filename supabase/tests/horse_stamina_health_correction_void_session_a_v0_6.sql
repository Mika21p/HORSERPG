begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000f601', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select public.correct_latest_horse_health_event(
  (select id from public.horse_health_events where race_result_id = (select id from public.race_results where horse_id = '00000000-0000-0000-0000-00000000f626') and status = 'ACTIVE'),
  50::smallint, 'concurrent correction', 'concurrent correction reason', '00000000-0000-0000-0000-00000000f718'
);
select pg_sleep(3);
commit;
