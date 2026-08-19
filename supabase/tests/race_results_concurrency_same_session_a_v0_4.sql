begin;
-- The test harness is postgres for its deliberate lock. The RPC call itself
-- below switches to a real authenticated GM context before business logic.
select id from public.confirmed_race_entries
where horse_id = '00000000-0000-0000-0000-00000000e301'
for update;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000e103', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select pg_sleep(3);
select id from public.record_race_result(
  (select id from public.confirmed_race_entries where horse_id = '00000000-0000-0000-0000-00000000e301'),
  (select id from public.actual_races where race_catalog_id = '00000000-0000-0000-0000-00000000e401'),
  1::smallint, 0::bigint, null, null, null
);
commit;
