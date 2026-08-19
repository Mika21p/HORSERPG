-- Persistent local-only setup for Race Results concurrency verification.

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
values ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-00000000e103', 'authenticated', 'authenticated', 'results-concurrency-gm@example.test', 'not-used', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now());

insert into public.owners (id, display_name, initial_funds)
values
  ('00000000-0000-0000-0000-00000000e201', 'Results Concurrency Owner A', 100000000),
  ('00000000-0000-0000-0000-00000000e202', 'Results Concurrency Owner B', 100000000);

insert into public.user_profiles (id, role, owner_id, display_name)
values ('00000000-0000-0000-0000-00000000e103', 'GM', null, 'Results Concurrency GM');

insert into public.game_state (id, current_wp_year, current_wp_month, current_wp_week, updated_by_user_id)
values (true, 2036, 6, 2, '00000000-0000-0000-0000-00000000e103')
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
  ('00000000-0000-0000-0000-00000000e301', 85101, 2033, 'Results Concurrent Same', 'MALE', 'BAY', 'Concurrency Sire A', 'Concurrency Line A', 'Concurrency Dam A', '00000000-0000-0000-0000-00000000e201', 'ACTIVE'),
  ('00000000-0000-0000-0000-00000000e302', 85102, 2033, 'Results Concurrent Conflict', 'FEMALE', 'CHESTNUT', 'Concurrency Sire B', 'Concurrency Line B', 'Concurrency Dam B', '00000000-0000-0000-0000-00000000e202', 'ACTIVE');

insert into public.race_catalog (id, name, grade, default_wp_month, default_wp_week, is_active)
values ('00000000-0000-0000-0000-00000000e401', 'Results Concurrency G2', 'G2', 6, 2, true);

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000e103', false);
select set_config('request.jwt.claim.role', 'authenticated', false);

select public.create_gm_confirmed_race_entry(
  '00000000-0000-0000-0000-00000000e301', 2036, 6::smallint, 2::smallint,
  'CATALOG'::public.race_entry_race_kind, '00000000-0000-0000-0000-00000000e401', null, null, null, null
);
select public.create_gm_confirmed_race_entry(
  '00000000-0000-0000-0000-00000000e302', 2036, 6::smallint, 2::smallint,
  'CATALOG'::public.race_entry_race_kind, '00000000-0000-0000-0000-00000000e401', null, null, null, null
);
select public.create_actual_race(
  2036, 6::smallint, 2::smallint,
  'CATALOG'::public.race_entry_race_kind, '00000000-0000-0000-0000-00000000e401', null
);

reset role;
