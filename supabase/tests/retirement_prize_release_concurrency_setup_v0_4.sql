-- Persistent local fixture for retirement/prize boundary concurrency tests.

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
values
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-00000000ec01', 'authenticated', 'authenticated', 'retirement-concurrency-player@example.test', 'not-used', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-00000000ec02', 'authenticated', 'authenticated', 'retirement-concurrency-gm@example.test', 'not-used', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now());

insert into public.owners (id, display_name, initial_funds)
values ('00000000-0000-0000-0000-00000000ec10', 'Retirement Concurrency Owner', 100000000);

insert into public.user_profiles (id, role, owner_id, display_name)
values
  ('00000000-0000-0000-0000-00000000ec01', 'PLAYER', '00000000-0000-0000-0000-00000000ec10', 'Retirement Concurrency Player'),
  ('00000000-0000-0000-0000-00000000ec02', 'GM', null, 'Retirement Concurrency GM');

insert into public.game_state (id, current_wp_year, current_wp_month, current_wp_week, updated_by_user_id)
values (true, 2042, 6, 5, '00000000-0000-0000-0000-00000000ec02')
on conflict (id) do update
set current_wp_year = excluded.current_wp_year,
    current_wp_month = excluded.current_wp_month,
    current_wp_week = excluded.current_wp_week,
    updated_by_user_id = excluded.updated_by_user_id;

insert into public.horses (
  id, horse_number, birth_year, foal_name, sex, coat_color,
  sire_name, sire_line, broodmare_sire_name, owner_id, life_stage
)
values
  ('00000000-0000-0000-0000-00000000ec20', 94201, 2037, 'Retirement Correction Race', 'MALE', 'BAY', 'CSire', 'CLine', 'CDam', '00000000-0000-0000-0000-00000000ec10', 'ACTIVE'),
  ('00000000-0000-0000-0000-00000000ec21', 94202, 2037, 'Retirement Void Race', 'FEMALE', 'BAY', 'VSire', 'VLine', 'VDam', '00000000-0000-0000-0000-00000000ec10', 'ACTIVE'),
  ('00000000-0000-0000-0000-00000000ec22', 94203, 2037, 'Retirement Late Record', 'MALE', 'BAY', 'RSire', 'RLine', 'RDam', '00000000-0000-0000-0000-00000000ec10', 'ACTIVE'),
  ('00000000-0000-0000-0000-00000000ec23', 94204, 2037, 'Retirement Parallel A', 'FEMALE', 'BAY', 'ASire', 'ALine', 'ADam', '00000000-0000-0000-0000-00000000ec10', 'ACTIVE'),
  ('00000000-0000-0000-0000-00000000ec24', 94205, 2037, 'Retirement Parallel B', 'MALE', 'BAY', 'BSire', 'BLine', 'BDam', '00000000-0000-0000-0000-00000000ec10', 'ACTIVE');

insert into public.race_catalog (id, name, grade, default_wp_month, default_wp_week, is_active)
values ('00000000-0000-0000-0000-00000000ec30', 'Retirement Concurrency G2', 'G2', 6, 5, true);

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000ec02', false);
select set_config('request.jwt.claim.role', 'authenticated', false);

select public.create_gm_confirmed_race_entry('00000000-0000-0000-0000-00000000ec20', 2042, 6::smallint, 5::smallint, 'CATALOG', '00000000-0000-0000-0000-00000000ec30', null, null, null, null);
select public.create_gm_confirmed_race_entry('00000000-0000-0000-0000-00000000ec21', 2042, 6::smallint, 5::smallint, 'CATALOG', '00000000-0000-0000-0000-00000000ec30', null, null, null, null);
select public.create_gm_confirmed_race_entry('00000000-0000-0000-0000-00000000ec22', 2042, 6::smallint, 5::smallint, 'CATALOG', '00000000-0000-0000-0000-00000000ec30', null, null, null, null);
select public.create_actual_race(2042, 6::smallint, 5::smallint, 'CATALOG', '00000000-0000-0000-0000-00000000ec30', null);
select public.record_race_result(
  (select id from public.confirmed_race_entries where horse_id = '00000000-0000-0000-0000-00000000ec20'),
  (select id from public.actual_races where race_catalog_id = '00000000-0000-0000-0000-00000000ec30'),
  1::smallint, 10000000::bigint, null, null, null
);
select public.record_race_result(
  (select id from public.confirmed_race_entries where horse_id = '00000000-0000-0000-0000-00000000ec21'),
  (select id from public.actual_races where race_catalog_id = '00000000-0000-0000-0000-00000000ec30'),
  1::smallint, 12000000::bigint, null, null, null
);

reset role;
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000ec01', false);
select set_config('request.jwt.claim.role', 'authenticated', false);
select public.submit_horse_retirement_request('00000000-0000-0000-0000-00000000ec20', null);
select public.submit_horse_retirement_request('00000000-0000-0000-0000-00000000ec21', null);
select public.submit_horse_retirement_request('00000000-0000-0000-0000-00000000ec22', null);
select public.submit_horse_retirement_request('00000000-0000-0000-0000-00000000ec23', null);
select public.submit_horse_retirement_request('00000000-0000-0000-0000-00000000ec24', null);
reset role;
