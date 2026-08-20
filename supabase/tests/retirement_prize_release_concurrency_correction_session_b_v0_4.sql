set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000ec02', false);
select set_config('request.jwt.claim.role', 'authenticated', false);
select public.correct_race_result(
  (select id from public.race_results where horse_id = '00000000-0000-0000-0000-00000000ec20' and status = 'CONFIRMED'),
  (select id from public.actual_races where race_catalog_id = '00000000-0000-0000-0000-00000000ec30'),
  1::smallint, 15000000::bigint, null, null, null, 'concurrent prize correction'
);
reset role;
