begin;
-- The test harness acquires its deliberate lock as postgres; the following
-- RPC call still runs under the authenticated GM claims required in production.
select id from public.confirmed_race_entries
where horse_id = '00000000-0000-0000-0000-00000000e302'
for update;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000e103', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select pg_sleep(3);
select id from public.record_race_result(
  (select id from public.confirmed_race_entries where horse_id = '00000000-0000-0000-0000-00000000e302'),
  (select id from public.actual_races where race_catalog_id = '00000000-0000-0000-0000-00000000e401'),
  2::smallint, 1000000::bigint, null, null, null
);
commit;
