set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000ec02', false);
select set_config('request.jwt.claim.role', 'authenticated', false);
select public.record_race_result(
  (select id from public.confirmed_race_entries where horse_id = '00000000-0000-0000-0000-00000000ec22'),
  (select id from public.actual_races where race_catalog_id = '00000000-0000-0000-0000-00000000ec30'),
  2::smallint, 13000000::bigint, null, null, null
);
reset role;
