set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000ec02', false);
select set_config('request.jwt.claim.role', 'authenticated', false);
select public.confirm_horse_retirement((select id from public.horse_retirement_requests where horse_id = '00000000-0000-0000-0000-00000000ec24'));
reset role;
