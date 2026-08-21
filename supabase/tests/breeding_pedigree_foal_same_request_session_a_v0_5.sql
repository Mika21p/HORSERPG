begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000c501', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select pg_advisory_xact_lock(hashtextextended('00000000-0000-0000-0000-00000000c801', 0));
select pg_sleep(2);
select public.create_foal(
  '00000000-0000-0000-0000-00000000c801', 95951, 2031, 'Concurrency Retry Foal', null, null, 'MALE', 'BAY',
  'MANUAL'::public.pedigree_parent_source_type, null, null, 'Manual Retry Sire', 'Manual Retry Line',
  'MANUAL'::public.pedigree_parent_source_type, null, null, 'Manual Retry Dam', 'Manual Retry BMS'
);
commit;
