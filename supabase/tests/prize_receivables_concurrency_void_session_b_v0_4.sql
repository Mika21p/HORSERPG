begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000fa03', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select id from public.void_race_result(
  (select id from public.race_results where horse_id = '00000000-0000-0000-0000-00000000fa30' and status = 'CONFIRMED'::public.race_result_status),
  'concurrent prize void'
);
commit;
