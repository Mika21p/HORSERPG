-- Persistent local-only fixture for the v0.4-A two-GM confirmation race.
-- The companion runner resets the database after verification.

begin;

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
values
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000004701', 'authenticated', 'authenticated', 'race-concurrency-player@example.test', 'not-used', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000004702', 'authenticated', 'authenticated', 'race-concurrency-gm@example.test', 'not-used', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now());

insert into public.owners (id, display_name, initial_funds)
values ('00000000-0000-0000-0000-000000004601', 'Race Concurrency Owner', 100000000);

insert into public.user_profiles (id, role, owner_id, display_name)
values
  ('00000000-0000-0000-0000-000000004701', 'PLAYER', '00000000-0000-0000-0000-000000004601', 'Race Concurrency Player'),
  ('00000000-0000-0000-0000-000000004702', 'GM', null, 'Race Concurrency GM');

insert into public.game_state (id, current_wp_year, current_wp_month, current_wp_week, updated_by_user_id)
values (true, 2040, 6, 1, '00000000-0000-0000-0000-000000004702');

insert into public.horses (
  id, horse_number, birth_year, foal_name, sex, coat_color,
  sire_name, sire_line, broodmare_sire_name, owner_id, life_stage
)
values (
  '00000000-0000-0000-0000-000000004801', 64801, 2037, 'Race Concurrency Horse', 'MALE', 'BAY',
  'Concurrency Sire', 'Concurrency Line', 'Concurrency Dam', '00000000-0000-0000-0000-000000004601', 'ACTIVE'
), (
  '00000000-0000-0000-0000-000000004802', 64802, 2037, 'Race Direct Concurrency Horse', 'FEMALE', 'CHESTNUT',
  'Direct Concurrency Sire', 'Direct Concurrency Line', 'Direct Concurrency Dam', '00000000-0000-0000-0000-000000004601', 'ACTIVE'
);

insert into public.race_catalog (id, name, grade, default_wp_month, default_wp_week)
values ('00000000-0000-0000-0000-000000004901', 'Race Concurrency Catalog', 'G3', 6, 2);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000004701', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select public.submit_race_entry_request(
  '00000000-0000-0000-0000-000000004801', 2040, 6::smallint, 2::smallint,
  'CATALOG'::public.race_entry_race_kind, '00000000-0000-0000-0000-000000004901', null, null, null, 'concurrent request A'
);
select public.submit_race_entry_request(
  '00000000-0000-0000-0000-000000004801', 2040, 6::smallint, 2::smallint,
  'CATALOG'::public.race_entry_race_kind, '00000000-0000-0000-0000-000000004901', null, null, null, 'concurrent request B'
);
select public.submit_race_entry_request(
  '00000000-0000-0000-0000-000000004802', 2040, 6::smallint, 3::smallint,
  'CATALOG'::public.race_entry_race_kind, '00000000-0000-0000-0000-000000004901', null, null, null, 'direct versus request concurrency'
);
reset role;

commit;
