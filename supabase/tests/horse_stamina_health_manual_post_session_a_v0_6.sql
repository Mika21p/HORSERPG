begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000f601', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select public.adjust_horse_stamina('00000000-0000-0000-0000-00000000f623', 60::smallint, 'concurrent manual', '00000000-0000-0000-0000-00000000f714');
select pg_sleep(3);
commit;
