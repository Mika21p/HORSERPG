-- Persistent local-only fixture for v0.6-A concurrency checks.
begin;

insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-00000000f601', 'authenticated', 'authenticated', 'health-concurrency-gm@example.test', 'not-used', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now());
insert into public.owners (id, display_name, initial_funds) values ('00000000-0000-0000-0000-00000000f610', 'Health Concurrency Owner', 100000000);
insert into public.user_profiles (id, role, owner_id, display_name) values ('00000000-0000-0000-0000-00000000f601', 'GM', null, 'Health Concurrency GM');
insert into public.game_state (id, current_wp_year, current_wp_month, current_wp_week, updated_by_user_id)
values (true, 2041, 5, 1, '00000000-0000-0000-0000-00000000f601')
on conflict (id) do update
set current_wp_year = excluded.current_wp_year,
    current_wp_month = excluded.current_wp_month,
    current_wp_week = excluded.current_wp_week,
    updated_by_user_id = excluded.updated_by_user_id;

insert into public.horses (id, horse_number, birth_year, foal_name, sex, coat_color, sire_name, sire_line, broodmare_sire_name, owner_id, life_stage)
values
  ('00000000-0000-0000-0000-00000000f621', 97101, 2038, 'Same Request Horse', 'MALE', 'BAY', 'Sire 1', 'Line 1', 'Dam 1', '00000000-0000-0000-0000-00000000f610', 'ACTIVE'),
  ('00000000-0000-0000-0000-00000000f622', 97102, 2038, 'Parallel Result Horse', 'FEMALE', 'BAY', 'Sire 2', 'Line 2', 'Dam 2', '00000000-0000-0000-0000-00000000f610', 'ACTIVE'),
  ('00000000-0000-0000-0000-00000000f623', 97103, 2038, 'Manual Post Horse', 'MALE', 'BAY', 'Sire 3', 'Line 3', 'Dam 3', '00000000-0000-0000-0000-00000000f610', 'ACTIVE'),
  ('00000000-0000-0000-0000-00000000f624', 97104, 2038, 'Record Void Horse', 'FEMALE', 'BAY', 'Sire 4', 'Line 4', 'Dam 4', '00000000-0000-0000-0000-00000000f610', 'ACTIVE'),
  ('00000000-0000-0000-0000-00000000f625', 97105, 2038, 'Void Manual Horse', 'MALE', 'BAY', 'Sire 5', 'Line 5', 'Dam 5', '00000000-0000-0000-0000-00000000f610', 'ACTIVE'),
  ('00000000-0000-0000-0000-00000000f626', 97106, 2038, 'Correction Void Horse', 'FEMALE', 'BAY', 'Sire 6', 'Line 6', 'Dam 6', '00000000-0000-0000-0000-00000000f610', 'ACTIVE');
insert into public.race_catalog (id, name, grade, default_wp_month, default_wp_week, is_active) values ('00000000-0000-0000-0000-00000000f630', 'Health Concurrency Catalog', 'G3', 5, 2, true);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000f601', true);
select set_config('request.jwt.claim.role', 'authenticated', true);

select public.create_gm_confirmed_race_entry('00000000-0000-0000-0000-00000000f621', 2041, 5::smallint, 2::smallint, 'CATALOG'::public.race_entry_race_kind, '00000000-0000-0000-0000-00000000f630', null, null, null, null);
select public.create_gm_confirmed_race_entry('00000000-0000-0000-0000-00000000f622', 2041, 5::smallint, 1::smallint, 'CATALOG'::public.race_entry_race_kind, '00000000-0000-0000-0000-00000000f630', null, null, null, null);
select public.create_gm_confirmed_race_entry('00000000-0000-0000-0000-00000000f622', 2041, 5::smallint, 2::smallint, 'CATALOG'::public.race_entry_race_kind, '00000000-0000-0000-0000-00000000f630', null, null, null, null);
select public.create_gm_confirmed_race_entry('00000000-0000-0000-0000-00000000f623', 2041, 5::smallint, 2::smallint, 'CATALOG'::public.race_entry_race_kind, '00000000-0000-0000-0000-00000000f630', null, null, null, null);
select public.create_gm_confirmed_race_entry('00000000-0000-0000-0000-00000000f624', 2041, 5::smallint, 2::smallint, 'CATALOG'::public.race_entry_race_kind, '00000000-0000-0000-0000-00000000f630', null, null, null, null);
select public.create_gm_confirmed_race_entry('00000000-0000-0000-0000-00000000f625', 2041, 5::smallint, 2::smallint, 'CATALOG'::public.race_entry_race_kind, '00000000-0000-0000-0000-00000000f630', null, null, null, null);
select public.create_gm_confirmed_race_entry('00000000-0000-0000-0000-00000000f626', 2041, 5::smallint, 2::smallint, 'CATALOG'::public.race_entry_race_kind, '00000000-0000-0000-0000-00000000f630', null, null, null, null);

select public.create_actual_race(2041, 5::smallint, 1::smallint, 'CATALOG'::public.race_entry_race_kind, '00000000-0000-0000-0000-00000000f630', null);
-- Establish the managed-stamina chain at WP week 1, before the two
-- concurrent post-race events append their week-1 and week-2 facts.
select public.adjust_horse_stamina('00000000-0000-0000-0000-00000000f622', 100::smallint, 'fixture parallel results', '00000000-0000-0000-0000-00000000f701');
update public.game_state
set current_wp_week = 2::smallint,
    updated_by_user_id = '00000000-0000-0000-0000-00000000f601'
where id;
select public.create_actual_race(2041, 5::smallint, 2::smallint, 'MAIDEN'::public.race_entry_race_kind, null, 'Health Concurrency Free Race');

select public.record_race_result(entry.id, actual.id, 1::smallint, 0::bigint, null, null, null)
from public.confirmed_race_entries entry join public.actual_races actual on (actual.wp_year, actual.wp_month, actual.wp_week) = (entry.wp_year, entry.wp_month, entry.wp_week)
where entry.horse_id = '00000000-0000-0000-0000-00000000f621';
select public.record_race_result(entry.id, actual.id, 2::smallint, 0::bigint, null, null, null)
from public.confirmed_race_entries entry join public.actual_races actual on (actual.wp_year, actual.wp_month, actual.wp_week) = (entry.wp_year, entry.wp_month, entry.wp_week)
where entry.horse_id = '00000000-0000-0000-0000-00000000f622' and entry.wp_week = 1;
select public.record_race_result(entry.id, actual.id, 3::smallint, 0::bigint, null, null, null)
from public.confirmed_race_entries entry join public.actual_races actual on (actual.wp_year, actual.wp_month, actual.wp_week) = (entry.wp_year, entry.wp_month, entry.wp_week)
where entry.horse_id = '00000000-0000-0000-0000-00000000f622' and entry.wp_week = 2;
select public.record_race_result(entry.id, actual.id, 4::smallint, 0::bigint, null, null, null)
from public.confirmed_race_entries entry join public.actual_races actual on (actual.wp_year, actual.wp_month, actual.wp_week) = (entry.wp_year, entry.wp_month, entry.wp_week)
where entry.horse_id = '00000000-0000-0000-0000-00000000f623';
select public.record_race_result(entry.id, actual.id, 5::smallint, 0::bigint, null, null, null)
from public.confirmed_race_entries entry join public.actual_races actual on (actual.wp_year, actual.wp_month, actual.wp_week) = (entry.wp_year, entry.wp_month, entry.wp_week)
where entry.horse_id = '00000000-0000-0000-0000-00000000f624';
select public.record_race_result(entry.id, actual.id, 6::smallint, 0::bigint, null, null, null)
from public.confirmed_race_entries entry join public.actual_races actual on (actual.wp_year, actual.wp_month, actual.wp_week) = (entry.wp_year, entry.wp_month, entry.wp_week)
where entry.horse_id = '00000000-0000-0000-0000-00000000f625';
select public.record_race_result(entry.id, actual.id, 7::smallint, 0::bigint, null, null, null)
from public.confirmed_race_entries entry join public.actual_races actual on (actual.wp_year, actual.wp_month, actual.wp_week) = (entry.wp_year, entry.wp_month, entry.wp_week)
where entry.horse_id = '00000000-0000-0000-0000-00000000f626';

select public.adjust_horse_stamina('00000000-0000-0000-0000-00000000f623', 70::smallint, 'fixture manual post', '00000000-0000-0000-0000-00000000f702');
select public.adjust_horse_stamina('00000000-0000-0000-0000-00000000f625', 90::smallint, 'fixture void manual', '00000000-0000-0000-0000-00000000f703');
select public.record_post_race_health('00000000-0000-0000-0000-00000000f704', (select id from public.race_results where horse_id = '00000000-0000-0000-0000-00000000f625'), 70::smallint, null, null, null, null, null, null, null, 'fixture latest post');
select public.adjust_horse_stamina('00000000-0000-0000-0000-00000000f626', 100::smallint, 'fixture correction void', '00000000-0000-0000-0000-00000000f705');
select public.record_post_race_health('00000000-0000-0000-0000-00000000f706', (select id from public.race_results where horse_id = '00000000-0000-0000-0000-00000000f626'), 80::smallint, null, null, null, null, null, null, null, 'fixture correction target');

reset role;
commit;
