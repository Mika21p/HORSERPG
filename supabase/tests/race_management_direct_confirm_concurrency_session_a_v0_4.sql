-- Session A: GM direct schedule holds the shared Horse lock so a concurrent
-- request confirmation must serialize behind it.

begin;
set local lock_timeout = '4s';
set local statement_timeout = '6s';
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000004702', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select public.create_gm_confirmed_race_entry(
  '00000000-0000-0000-0000-000000004802', 2040, 6::smallint, 3::smallint,
  'CATALOG'::public.race_entry_race_kind, '00000000-0000-0000-0000-000000004901', null, null, null, 'direct concurrency winner'
);
select pg_sleep(3);
commit;
