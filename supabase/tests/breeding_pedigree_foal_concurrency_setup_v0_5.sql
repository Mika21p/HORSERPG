-- Persistent local-only fixture for the v0.5-A concurrency runner.

begin;

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
values (
  '00000000-0000-0000-0000-000000000000',
  '00000000-0000-0000-0000-00000000c501',
  'authenticated', 'authenticated', 'breeding-concurrency-gm@example.test',
  'not-used', now(), '{"provider":"email","providers":["email"]}'::jsonb,
  '{}'::jsonb, now(), now()
);

insert into public.user_profiles (id, role, owner_id, display_name)
values ('00000000-0000-0000-0000-00000000c501', 'GM', null, 'Breeding Concurrency GM');

select set_config('horserpg.retirement_transition', 'on', true);
insert into public.horses (
  id, horse_number, birth_year, foal_name, sex, coat_color,
  sire_name, sire_line, broodmare_sire_name, life_stage
)
values
  ('00000000-0000-0000-0000-00000000c701', 95901, 2020, 'Concurrency Sire', 'MALE', 'BAY', 'Concurrency Sire Sire', 'Concurrency Sire Line', 'Concurrency Sire BMS', 'RETIRED'),
  ('00000000-0000-0000-0000-00000000c702', 95902, 2020, 'Concurrency Dam', 'FEMALE', 'BAY', 'Concurrency Dam Sire', 'Concurrency Dam Line', 'Concurrency Dam BMS', 'RETIRED'),
  ('00000000-0000-0000-0000-00000000c703', 95903, 2020, 'Parallel Sire', 'MALE', 'BAY', 'Parallel Sire Sire', 'Parallel Sire Line', 'Parallel Sire BMS', 'RETIRED');
select set_config('horserpg.retirement_transition', '', true);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000c501', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select public.activate_breeding_candidate('00000000-0000-0000-0000-00000000c701', 'deactivation race target');
select public.activate_breeding_candidate('00000000-0000-0000-0000-00000000c703', 'parallel Foal sire');
reset role;

commit;
