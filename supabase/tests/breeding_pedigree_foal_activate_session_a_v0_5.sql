begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000c501', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select id from public.horses where id = '00000000-0000-0000-0000-00000000c702' for update;
select pg_sleep(2);
select public.activate_breeding_candidate('00000000-0000-0000-0000-00000000c702', 'activation race A');
commit;
