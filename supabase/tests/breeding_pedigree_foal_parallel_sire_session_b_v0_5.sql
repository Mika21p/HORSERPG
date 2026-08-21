begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000c501', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select public.create_foal(
  '00000000-0000-0000-0000-00000000c803', 95953, 2031, 'Parallel Sire Foal B', null, null, 'FEMALE', 'BAY',
  'INTERNAL'::public.pedigree_parent_source_type, '00000000-0000-0000-0000-00000000c703', null, null, null,
  'MANUAL'::public.pedigree_parent_source_type, null, null, 'Parallel Dam B', 'Parallel BMS B'
);
commit;
