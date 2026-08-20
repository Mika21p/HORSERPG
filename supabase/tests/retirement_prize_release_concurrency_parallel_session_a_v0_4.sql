begin;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000ec02', false);
select set_config('request.jwt.claim.role', 'authenticated', false);
select id from public.horse_retirement_requests where horse_id = '00000000-0000-0000-0000-00000000ec23' and status = 'PENDING' for update;
select id from public.horses where id = '00000000-0000-0000-0000-00000000ec23' for update;
select pg_sleep(3);
select public.confirm_horse_retirement((select id from public.horse_retirement_requests where horse_id = '00000000-0000-0000-0000-00000000ec23'));
commit;
