set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000ec02', false);
select set_config('request.jwt.claim.role', 'authenticated', false);
select public.void_race_result(
  (select id from public.race_results where horse_id = '00000000-0000-0000-0000-00000000ec21' and status = 'CONFIRMED'),
  'concurrent prize void'
);
reset role;
