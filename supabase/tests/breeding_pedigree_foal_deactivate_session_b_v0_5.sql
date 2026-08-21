begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000c501', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select public.deactivate_breeding_candidate('00000000-0000-0000-0000-00000000c701', 'deactivation race B');
commit;
