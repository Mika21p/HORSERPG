begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000c501', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select id from public.horses where id = '00000000-0000-0000-0000-00000000c703' for share;
select pg_sleep(2);
select public.create_foal(
  '00000000-0000-0000-0000-00000000c802', 95952, 2031, 'Parallel Sire Foal A', null, null, 'MALE', 'BAY',
  'INTERNAL'::public.pedigree_parent_source_type, '00000000-0000-0000-0000-00000000c703', null, null, null,
  'MANUAL'::public.pedigree_parent_source_type, null, null, 'Parallel Dam A', 'Parallel BMS A'
);
commit;
