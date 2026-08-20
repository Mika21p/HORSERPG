-- Persistent local-only setup for Prize Receivables correction-vs-void testing.

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
values ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-00000000fa03', 'authenticated', 'authenticated', 'prize-concurrency-gm@example.test', 'not-used', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now());

insert into public.owners (id, display_name, initial_funds)
values ('00000000-0000-0000-0000-00000000fa20', 'Prize Concurrency Owner', 100000000);

insert into public.user_profiles (id, role, owner_id, display_name)
values ('00000000-0000-0000-0000-00000000fa03', 'GM', null, 'Prize Concurrency GM');

insert into public.game_state (id, current_wp_year, current_wp_month, current_wp_week, updated_by_user_id)
values (true, 2038, 7, 2, '00000000-0000-0000-0000-00000000fa03')
on conflict (id) do update
set current_wp_year = excluded.current_wp_year,
    current_wp_month = excluded.current_wp_month,
    current_wp_week = excluded.current_wp_week,
    updated_by_user_id = excluded.updated_by_user_id;

insert into public.horses (
  id, horse_number, birth_year, foal_name, sex, coat_color,
  sire_name, sire_line, broodmare_sire_name, owner_id, life_stage
)
values ('00000000-0000-0000-0000-00000000fa30', 87101, 2035, 'Prize Concurrency Horse', 'MALE', 'BAY', 'Prize Concurrent Sire', 'Prize Concurrent Line', 'Prize Concurrent Dam', '00000000-0000-0000-0000-00000000fa20', 'ACTIVE');

insert into public.race_catalog (id, name, grade, default_wp_month, default_wp_week, is_active)
values ('00000000-0000-0000-0000-00000000fa40', 'Prize Concurrency G3', 'G3', 7, 2, true);

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000fa03', false);
select set_config('request.jwt.claim.role', 'authenticated', false);

select public.create_gm_confirmed_race_entry(
  '00000000-0000-0000-0000-00000000fa30', 2038, 7::smallint, 2::smallint,
  'CATALOG'::public.race_entry_race_kind, '00000000-0000-0000-0000-00000000fa40', null, null, null, null
);
select public.create_actual_race(
  2038, 7::smallint, 2::smallint,
  'CATALOG'::public.race_entry_race_kind, '00000000-0000-0000-0000-00000000fa40', null
);
select public.record_race_result(
  (select id from public.confirmed_race_entries where horse_id = '00000000-0000-0000-0000-00000000fa30'),
  (select id from public.actual_races where race_catalog_id = '00000000-0000-0000-0000-00000000fa40'),
  1::smallint, 5000000::bigint, null, null, null
);

reset role;
