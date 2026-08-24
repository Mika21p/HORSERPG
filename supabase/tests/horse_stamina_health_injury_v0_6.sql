-- Local SQL verification for HorseRPG v0.6-A stamina, post-race health, and
-- injury lifecycle. Run after `npx supabase db reset`. All rows roll back.

begin;

do $$
declare
  v_function text;
begin
  if array_to_string(enum_range(null::public.injury_status)::text[], ',') <> 'ACTIVE,RECOVERED,CANCELLED,VOIDED' then
    raise exception 'injury_status must retain ACTIVE/RECOVERED/CANCELLED and add VOIDED';
  end if;

  if not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'horses' and column_name = 'current_stamina' and udt_name = 'int2' and is_nullable = 'YES') then
    raise exception 'horses.current_stamina smallint nullable column is missing';
  end if;
  if not exists (select 1 from pg_tables where schemaname = 'public' and tablename = 'horse_health_events')
    or not exists (select 1 from pg_tables where schemaname = 'public' and tablename = 'injury_private_metadata')
    or not exists (select 1 from pg_views where schemaname = 'public' and viewname = 'horse_health_events_public')
    or not exists (select 1 from pg_views where schemaname = 'public' and viewname = 'injuries_public') then
    raise exception 'v0.6 health table or safe view is missing';
  end if;
  if not (select relrowsecurity from pg_class where oid = 'public.horse_health_events'::regclass) then
    raise exception 'horse_health_events must enable RLS';
  end if;
  if not (select relrowsecurity from pg_class where oid = 'public.injury_private_metadata'::regclass) then
    raise exception 'injury_private_metadata must enable RLS';
  end if;
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'injuries'
      and column_name in ('source_health_event_id', 'resolved_by_user_id', 'resolved_at', 'resolution_reason', 'voided_by_user_id', 'voided_at', 'void_reason')
  ) then raise exception 'v0.6 lifecycle metadata must not expand the legacy injuries row'; end if;
  if has_table_privilege('authenticated', 'public.injuries', 'DELETE')
    or not has_table_privilege('authenticated', 'public.injuries', 'INSERT, UPDATE') then
    raise exception 'injuries must retain INSERT/UPDATE but not DELETE for authenticated';
  end if;
  if not exists (select 1 from pg_indexes where schemaname = 'public' and indexname = 'horse_health_events_one_active_post_race_per_result_idx')
    or not exists (select 1 from pg_indexes where schemaname = 'public' and indexname = 'horse_health_events_horse_sequence_idx') then
    raise exception 'health-event uniqueness indexes are missing';
  end if;

  foreach v_function in array array[
    'public.record_post_race_health(uuid,uuid,smallint,integer,smallint,smallint,integer,smallint,smallint,text,text)'::text,
    'public.adjust_horse_stamina(uuid,smallint,text,uuid)'::text,
    'public.create_manual_injury(uuid,integer,smallint,smallint,integer,smallint,smallint,text)'::text,
    'public.resolve_injury(uuid,text)'::text,
    'public.void_injury(uuid,text)'::text,
    'public.correct_latest_horse_health_event(uuid,smallint,text,text,uuid,integer,smallint,smallint,integer,smallint,smallint,text)'::text,
    'public.void_latest_horse_health_event(uuid,text)'::text,
    'public.void_race_result(uuid,text)'::text
  ] loop
    if not exists (
      select 1 from pg_proc p
      where p.oid = v_function::regprocedure and p.prosecdef and p.proconfig::text like '%search_path=%'
    ) then raise exception 'missing insecure health RPC: %', v_function; end if;
    if has_function_privilege('public', v_function::regprocedure, 'EXECUTE')
      or has_function_privilege('anon', v_function::regprocedure, 'EXECUTE')
      or has_function_privilege('service_role', v_function::regprocedure, 'EXECUTE')
      or not has_function_privilege('authenticated', v_function::regprocedure, 'EXECUTE') then
      raise exception 'health RPC has incorrect ACL: %', v_function;
    end if;
  end loop;

  foreach v_function in array array[
    'public.apply_horse_stamina_transition(uuid,smallint)'::text,
    'public.void_source_injuries_for_health_event(uuid,text)'::text,
    'public.void_latest_horse_health_event_locked(uuid,text,text)'::text,
    'public.assert_health_event_wp_time_appendable(uuid,integer,smallint,smallint)'::text,
    'public.assert_horse_current_stamina_chain(public.horses)'::text
    ,'public.enforce_injury_private_metadata_source()'::text
    ,'public.enforce_injury_source_health_event_invariant()'::text
  ] loop
    if has_function_privilege('public', v_function::regprocedure, 'EXECUTE')
      or has_function_privilege('anon', v_function::regprocedure, 'EXECUTE')
      or has_function_privilege('authenticated', v_function::regprocedure, 'EXECUTE')
      or has_function_privilege('service_role', v_function::regprocedure, 'EXECUTE') then
      raise exception 'health helper is callable by a client: %', v_function;
    end if;
  end loop;

  if has_table_privilege('public', 'public.horse_health_events_public', 'SELECT')
    or has_table_privilege('anon', 'public.horse_health_events_public', 'SELECT')
    or not has_table_privilege('authenticated', 'public.horse_health_events_public', 'SELECT')
    or has_table_privilege('authenticated', 'public.horse_health_events_public', 'INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER') then
    raise exception 'horse_health_events_public has an incorrect ACL';
  end if;
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'horse_health_events_public'
      and column_name in ('notes', 'request_id', 'confirmed_by_user_id', 'voided_by_user_id', 'void_reason')
  ) then raise exception 'health public view leaks private data'; end if;
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'injuries_public'
      and column_name in ('source_health_event_id', 'resolved_by_user_id', 'resolved_at', 'resolution_reason', 'voided_by_user_id', 'voided_at', 'void_reason')
  ) then raise exception 'injuries_public leaks lifecycle metadata'; end if;
end;
$$;

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-00000000e601', 'authenticated', 'authenticated', 'health-player@example.test', 'not-used', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-00000000e602', 'authenticated', 'authenticated', 'health-gm@example.test', 'not-used', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now());

insert into public.owners (id, display_name, initial_funds)
values ('00000000-0000-0000-0000-00000000e610', 'Health Test Owner', 100000000);

insert into public.user_profiles (id, role, owner_id, display_name)
values
  ('00000000-0000-0000-0000-00000000e601', 'PLAYER', '00000000-0000-0000-0000-00000000e610', 'Health Player'),
  ('00000000-0000-0000-0000-00000000e602', 'GM', null, 'Health GM');

insert into public.game_state (id, current_wp_year, current_wp_month, current_wp_week, updated_by_user_id)
values (true, 2040, 5, 4, '00000000-0000-0000-0000-00000000e602');

-- Ordinary Horse creation cannot sneak in a managed stamina value.
do $$
begin
  begin
    insert into public.horses (
      horse_number, birth_year, foal_name, sex, coat_color, sire_name, sire_line, broodmare_sire_name, life_stage, current_stamina
    ) values (96099, 2038, 'Illegal Stamina Horse', 'MALE', 'BAY', 'Sire', 'Line', 'Dam', 'ACTIVE', 80);
    raise exception 'ordinary Horse insert accepted non-NULL stamina' using errcode = 'XX000';
  exception when check_violation then null;
  end;
end;
$$;

insert into public.horses (
  id, horse_number, birth_year, foal_name, sex, coat_color,
  sire_name, sire_line, broodmare_sire_name, owner_id, life_stage
) values
  ('00000000-0000-0000-0000-00000000e621', 96101, 2037, 'Managed Health Horse', 'MALE', 'BAY', 'Health Sire A', 'Health Line A', 'Health Dam A', '00000000-0000-0000-0000-00000000e610', 'ACTIVE'),
  ('00000000-0000-0000-0000-00000000e622', 96102, 2037, 'Unmanaged Health Horse', 'FEMALE', 'CHESTNUT', 'Health Sire B', 'Health Line B', 'Health Dam B', '00000000-0000-0000-0000-00000000e610', 'ACTIVE'),
  ('00000000-0000-0000-0000-00000000e623', 96103, 2037, 'Void Result Health Horse', 'MALE', 'BROWN', 'Health Sire C', 'Health Line C', 'Health Dam C', '00000000-0000-0000-0000-00000000e610', 'ACTIVE'),
  ('00000000-0000-0000-0000-00000000e624', 96104, 2037, 'Non Latest Result Horse', 'FEMALE', 'GREY', 'Health Sire D', 'Health Line D', 'Health Dam D', '00000000-0000-0000-0000-00000000e610', 'ACTIVE'),
  ('00000000-0000-0000-0000-00000000e625', 96105, 2037, 'Manual Injury Horse', 'MALE', 'BAY', 'Health Sire E', 'Health Line E', 'Health Dam E', '00000000-0000-0000-0000-00000000e610', 'ACTIVE'),
  ('00000000-0000-0000-0000-00000000e626', 96106, 2037, 'Managed State Validation Horse', 'MALE', 'BAY', 'Health Sire F', 'Health Line F', 'Health Dam F', '00000000-0000-0000-0000-00000000e610', 'ACTIVE'),
  ('00000000-0000-0000-0000-00000000e627', 96107, 2037, 'Unmanaged State Validation Horse', 'FEMALE', 'BAY', 'Health Sire G', 'Health Line G', 'Health Dam G', '00000000-0000-0000-0000-00000000e610', 'ACTIVE');

insert into public.race_catalog (id, name, grade, default_wp_month, default_wp_week, is_active)
values ('00000000-0000-0000-0000-00000000e630', 'Health Test Catalog', 'G3', 5, 4, true);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000e602', true);
select set_config('request.jwt.claim.role', 'authenticated', true);

-- Core GM legacy injury administration remains INSERT/UPDATE compatible but
-- never gains DELETE. These rows intentionally have no v0.6 source metadata.
insert into public.injuries (
  id, horse_id, status,
  wp_start_year, wp_start_month, wp_start_week,
  wp_end_year, wp_end_month, wp_end_week, notes, confirmed_by_user_id
) values (
  '00000000-0000-0000-0000-00000000e690', '00000000-0000-0000-0000-00000000e625', 'ACTIVE',
  2040, 6, 1, 2040, 6, 2, 'legacy GM injury', '00000000-0000-0000-0000-00000000e602'
);
update public.injuries set notes = 'legacy GM injury updated' where id = '00000000-0000-0000-0000-00000000e690';
do $$
begin
  begin
    delete from public.injuries where id = '00000000-0000-0000-0000-00000000e690';
    raise exception 'GM direct injury DELETE was accepted' using errcode = 'XX000';
  exception when insufficient_privilege then null;
  end;
end;
$$;

-- A NULL-managed Horse and a zero-stamina Horse both pass existing schedule
-- rules. Stamina is deliberately not a race-entry hard constraint.
select public.create_gm_confirmed_race_entry('00000000-0000-0000-0000-00000000e621', 2040, 5::smallint, 4::smallint, 'CATALOG'::public.race_entry_race_kind, '00000000-0000-0000-0000-00000000e630', null, null, null, null);
select public.create_gm_confirmed_race_entry('00000000-0000-0000-0000-00000000e622', 2040, 5::smallint, 4::smallint, 'CATALOG'::public.race_entry_race_kind, '00000000-0000-0000-0000-00000000e630', null, null, null, null);
select public.create_gm_confirmed_race_entry('00000000-0000-0000-0000-00000000e623', 2040, 5::smallint, 4::smallint, 'CATALOG'::public.race_entry_race_kind, '00000000-0000-0000-0000-00000000e630', null, null, null, null);
select public.create_gm_confirmed_race_entry('00000000-0000-0000-0000-00000000e624', 2040, 5::smallint, 4::smallint, 'CATALOG'::public.race_entry_race_kind, '00000000-0000-0000-0000-00000000e630', null, null, null, null);
select public.create_gm_confirmed_race_entry('00000000-0000-0000-0000-00000000e626', 2040, 5::smallint, 4::smallint, 'CATALOG'::public.race_entry_race_kind, '00000000-0000-0000-0000-00000000e630', null, null, null, null);
select public.create_gm_confirmed_race_entry('00000000-0000-0000-0000-00000000e627', 2040, 5::smallint, 4::smallint, 'CATALOG'::public.race_entry_race_kind, '00000000-0000-0000-0000-00000000e630', null, null, null, null);

select public.create_actual_race(2040, 5::smallint, 4::smallint, 'CATALOG'::public.race_entry_race_kind, '00000000-0000-0000-0000-00000000e630', null);
select set_config('test.health.actual_race_id', (select id::text from public.actual_races where race_catalog_id = '00000000-0000-0000-0000-00000000e630'), true);

select public.record_race_result(entry.id, current_setting('test.health.actual_race_id', true)::uuid, 1::smallint, 0::bigint, null, null, null)
from public.confirmed_race_entries entry where entry.horse_id = '00000000-0000-0000-0000-00000000e621';
select public.record_race_result(entry.id, current_setting('test.health.actual_race_id', true)::uuid, 2::smallint, 0::bigint, null, null, null)
from public.confirmed_race_entries entry where entry.horse_id = '00000000-0000-0000-0000-00000000e622';
select public.record_race_result(entry.id, current_setting('test.health.actual_race_id', true)::uuid, 3::smallint, 0::bigint, null, null, null)
from public.confirmed_race_entries entry where entry.horse_id = '00000000-0000-0000-0000-00000000e623';
select public.record_race_result(entry.id, current_setting('test.health.actual_race_id', true)::uuid, 4::smallint, 0::bigint, null, null, null)
from public.confirmed_race_entries entry where entry.horse_id = '00000000-0000-0000-0000-00000000e624';
select public.record_race_result(entry.id, current_setting('test.health.actual_race_id', true)::uuid, 5::smallint, 0::bigint, null, null, null)
from public.confirmed_race_entries entry where entry.horse_id = '00000000-0000-0000-0000-00000000e626';
select public.record_race_result(entry.id, current_setting('test.health.actual_race_id', true)::uuid, 6::smallint, 0::bigint, null, null, null)
from public.confirmed_race_entries entry where entry.horse_id = '00000000-0000-0000-0000-00000000e627';

select set_config('test.health.managed_result_id', (select id::text from public.race_results where horse_id = '00000000-0000-0000-0000-00000000e621' and status = 'CONFIRMED'), true);
select set_config('test.health.unmanaged_result_id', (select id::text from public.race_results where horse_id = '00000000-0000-0000-0000-00000000e622' and status = 'CONFIRMED'), true);
select set_config('test.health.void_result_id', (select id::text from public.race_results where horse_id = '00000000-0000-0000-0000-00000000e623' and status = 'CONFIRMED'), true);
select set_config('test.health.nonlatest_result_id', (select id::text from public.race_results where horse_id = '00000000-0000-0000-0000-00000000e624' and status = 'CONFIRMED'), true);
select set_config('test.health.managed_validation_result_id', (select id::text from public.race_results where horse_id = '00000000-0000-0000-0000-00000000e626' and status = 'CONFIRMED'), true);
select set_config('test.health.unmanaged_validation_result_id', (select id::text from public.race_results where horse_id = '00000000-0000-0000-0000-00000000e627' and status = 'CONFIRMED'), true);

-- NULL -> 0 enables management. Zero is a real managed value and may race.
select public.adjust_horse_stamina('00000000-0000-0000-0000-00000000e621', 0::smallint, 'enable at exhausted state', '00000000-0000-0000-0000-00000000e701');
select public.adjust_horse_stamina('00000000-0000-0000-0000-00000000e626', 80::smallint, 'enable for POST_RACE validation', '00000000-0000-0000-0000-00000000e718');
select public.record_post_race_health('00000000-0000-0000-0000-00000000e702', current_setting('test.health.managed_result_id', true)::uuid, 0::smallint, null, null, null, null, null, null, null, 'managed no change');

-- NULL -> NULL is a valid completed post-race fact and retries return it.
select public.record_post_race_health('00000000-0000-0000-0000-00000000e703', current_setting('test.health.unmanaged_result_id', true)::uuid, null, null, null, null, null, null, null, null, 'unmanaged completed');
select public.record_post_race_health('00000000-0000-0000-0000-00000000e703', current_setting('test.health.unmanaged_result_id', true)::uuid, null, null, null, null, null, null, null, null, 'unmanaged completed');

-- Unmanaged post-race injury is equally valid and leaves stamina NULL.
select public.record_post_race_health('00000000-0000-0000-0000-00000000e704', current_setting('test.health.void_result_id', true)::uuid, null, 2040, 5::smallint, 4::smallint, 2040, 6::smallint, 1::smallint, 'post-race injury', 'unmanaged with injury');

-- A later manual event makes a previous post-race event non-latest.
select public.adjust_horse_stamina('00000000-0000-0000-0000-00000000e624', 60::smallint, 'enable for non-latest void test', '00000000-0000-0000-0000-00000000e705');
select public.record_post_race_health('00000000-0000-0000-0000-00000000e706', current_setting('test.health.nonlatest_result_id', true)::uuid, 40::smallint, null, null, null, null, null, null, null, 'will become non-latest');
select public.adjust_horse_stamina('00000000-0000-0000-0000-00000000e624', 30::smallint, 'later manual fact', '00000000-0000-0000-0000-00000000e707');

do $$
declare
  v_event_id uuid;
begin
  if (select current_stamina from public.horses where id = '00000000-0000-0000-0000-00000000e621') <> 0 then
    raise exception 'zero stamina was not retained as a managed value';
  end if;
  if (select current_stamina from public.horses where id = '00000000-0000-0000-0000-00000000e622') is not null
    or (select current_stamina from public.horses where id = '00000000-0000-0000-0000-00000000e623') is not null then
    raise exception 'unmanaged post-race flow changed NULL stamina';
  end if;
  if (select count(*) from public.horse_health_events where race_result_id = current_setting('test.health.unmanaged_result_id', true)::uuid and status = 'ACTIVE') <> 1 then
    raise exception 'same post-race request did not stay idempotent';
  end if;
  if not exists (
    select 1
    from public.injuries as injury
    join public.injury_private_metadata as metadata on metadata.injury_id = injury.id
    where injury.horse_id = '00000000-0000-0000-0000-00000000e623'
      and injury.status = 'ACTIVE'
      and metadata.source_health_event_id is not null
  ) then
    raise exception 'unmanaged post-race injury was not created';
  end if;

  begin
    update public.horses set current_stamina = 80 where id = '00000000-0000-0000-0000-00000000e621';
    raise exception 'direct GM stamina update was accepted' using errcode = 'XX000';
  exception when check_violation then null;
  end;
  begin
    perform public.adjust_horse_stamina('00000000-0000-0000-0000-00000000e621', 0::smallint, 'manual no-op', '00000000-0000-0000-0000-00000000e708');
    raise exception 'manual 0 -> 0 no-op was accepted' using errcode = 'XX000';
  exception when check_violation then null;
  end;
  begin
    perform public.record_post_race_health('00000000-0000-0000-0000-00000000e709', current_setting('test.health.managed_validation_result_id', true)::uuid, null, null, null, null, null, null, null, null, 'illegal disable');
    raise exception 'POST_RACE disabled managed stamina' using errcode = 'XX000';
  exception when check_violation then null;
  end;
  begin
    perform public.record_post_race_health('00000000-0000-0000-0000-00000000e710', current_setting('test.health.unmanaged_validation_result_id', true)::uuid, 80::smallint, null, null, null, null, null, null, null, 'illegal enable');
    raise exception 'POST_RACE enabled unmanaged stamina' using errcode = 'XX000';
  exception when check_violation then null;
  end;

  select id into v_event_id from public.horse_health_events where race_result_id = current_setting('test.health.nonlatest_result_id', true)::uuid and status = 'ACTIVE';
  begin
    perform public.correct_latest_horse_health_event(v_event_id, 20::smallint, 'bad old correction', 'must reject non-latest', '00000000-0000-0000-0000-00000000e711');
    raise exception 'non-latest health correction was accepted' using errcode = 'XX000';
  exception when check_violation then null;
  end;
  begin
    perform public.void_race_result(current_setting('test.health.nonlatest_result_id', true)::uuid, 'cannot void historical health');
    raise exception 'result with non-latest health was voided' using errcode = 'XX000';
  exception when check_violation then null;
  end;
end;
$$;

-- Source-linked injury facts are private and are only created by the
-- controlled POST_RACE flow. Exercise both the database invariant (as local
-- postgres) and the ordinary GM direct-write denial.
reset role;
do $$
declare
  v_post_source_id uuid;
  v_manual_source_id uuid;
  v_source_injury_id uuid;
begin
  select id into v_post_source_id from public.horse_health_events where request_id = '00000000-0000-0000-0000-00000000e704';
  select id into v_manual_source_id from public.horse_health_events where request_id = '00000000-0000-0000-0000-00000000e701';
  select metadata.injury_id into v_source_injury_id
  from public.injury_private_metadata as metadata
  where metadata.source_health_event_id = v_post_source_id;

  insert into public.injuries (id, horse_id, status, wp_start_year, wp_start_month, wp_start_week, wp_end_year, wp_end_month, wp_end_week)
  values ('00000000-0000-0000-0000-00000000e691', '00000000-0000-0000-0000-00000000e621', 'ACTIVE', 2040, 6, 1, 2040, 6, 2);
  perform set_config('horserpg.injury_source_transition', 'on', true);
  begin
    insert into public.injury_private_metadata (injury_id, source_health_event_id)
    values ('00000000-0000-0000-0000-00000000e691', v_manual_source_id);
    raise exception 'MANUAL_ADJUSTMENT was accepted as an injury source' using errcode = 'XX000';
  exception when check_violation then null;
  end;

  insert into public.injuries (id, horse_id, status, wp_start_year, wp_start_month, wp_start_week, wp_end_year, wp_end_month, wp_end_week)
  values ('00000000-0000-0000-0000-00000000e692', '00000000-0000-0000-0000-00000000e625', 'ACTIVE', 2040, 6, 1, 2040, 6, 2);
  perform set_config('horserpg.injury_source_transition', 'on', true);
  begin
    insert into public.injury_private_metadata (injury_id, source_health_event_id)
    values ('00000000-0000-0000-0000-00000000e692', v_post_source_id);
    raise exception 'a mismatched-Horse POST_RACE source was accepted' using errcode = 'XX000';
  exception when check_violation then null;
  end;

  perform set_config('horserpg.health_event_transition', 'on', true);
  begin
    update public.horse_health_events
    set status = 'VOIDED'::public.horse_health_event_status,
        voided_at = clock_timestamp(),
        void_reason = 'must fail while its injury is effective'
    where id = v_post_source_id;
    raise exception 'effective source injury allowed its health event to be voided' using errcode = 'XX000';
  exception when check_violation then null;
  end;

  perform set_config('horserpg.injury_lifecycle_transition', 'on', true);
  update public.injuries set status = 'RECOVERED'::public.injury_status where id = v_source_injury_id;
  perform set_config('horserpg.health_event_transition', 'on', true);
  begin
    update public.horse_health_events
    set status = 'VOIDED'::public.horse_health_event_status,
        voided_at = clock_timestamp(),
        void_reason = 'must fail for recovered source injury'
    where id = v_post_source_id;
    raise exception 'RECOVERED source injury allowed its health event to be voided' using errcode = 'XX000';
  exception when check_violation then null;
  end;

  perform set_config('horserpg.injury_lifecycle_transition', 'on', true);
  update public.injuries set status = 'CANCELLED'::public.injury_status where id = v_source_injury_id;
  perform set_config('horserpg.health_event_transition', 'on', true);
  begin
    update public.horse_health_events
    set status = 'VOIDED'::public.horse_health_event_status,
        voided_at = clock_timestamp(),
        void_reason = 'must fail for cancelled source injury'
    where id = v_post_source_id;
    raise exception 'CANCELLED source injury allowed its health event to be voided' using errcode = 'XX000';
  exception when check_violation then null;
  end;
end;
$$;

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000e602', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
do $$
begin
  begin
    update public.injury_private_metadata
    set source_health_event_id = null
    where source_health_event_id = (select id from public.horse_health_events where request_id = '00000000-0000-0000-0000-00000000e704');
    raise exception 'GM directly rewrote a controlled injury source' using errcode = 'XX000';
  exception when insufficient_privilege then null;
  end;
end;
$$;

-- Correct the latest unmanaged injury event. Its old source Injury becomes
-- VOIDED, replacement is active, and current stamina remains NULL.
select set_config('test.health.correction_target_id', (
  select id::text
  from public.horse_health_events
  where race_result_id = current_setting('test.health.void_result_id', true)::uuid
    and status = 'ACTIVE'
), true);
select public.correct_latest_horse_health_event(
  current_setting('test.health.correction_target_id', true)::uuid,
  null, 'corrected post-race without injury', 'injury was recorded in error', '00000000-0000-0000-0000-00000000e712',
  null, null, null, null, null, null, null
);

-- A correction request id is idempotent only when every correction fact,
-- including reason and replacement injury shape, is exactly the same.
do $$
begin
  perform public.correct_latest_horse_health_event(
    current_setting('test.health.correction_target_id', true)::uuid,
    null, 'corrected post-race without injury', 'injury was recorded in error', '00000000-0000-0000-0000-00000000e712',
    null, null, null, null, null, null, null
  );
  begin
    perform public.correct_latest_horse_health_event(current_setting('test.health.correction_target_id', true)::uuid, 1::smallint, 'corrected post-race without injury', 'injury was recorded in error', '00000000-0000-0000-0000-00000000e712');
    raise exception 'same correction request accepted different stamina' using errcode = 'XX000';
  exception when unique_violation then null;
  end;
  begin
    perform public.correct_latest_horse_health_event(current_setting('test.health.correction_target_id', true)::uuid, null, 'different notes', 'injury was recorded in error', '00000000-0000-0000-0000-00000000e712');
    raise exception 'same correction request accepted different notes' using errcode = 'XX000';
  exception when unique_violation then null;
  end;
  begin
    perform public.correct_latest_horse_health_event(current_setting('test.health.correction_target_id', true)::uuid, null, 'corrected post-race without injury', 'different correction reason', '00000000-0000-0000-0000-00000000e712');
    raise exception 'same correction request accepted different reason' using errcode = 'XX000';
  exception when unique_violation then null;
  end;
  begin
    perform public.correct_latest_horse_health_event(current_setting('test.health.correction_target_id', true)::uuid, null, 'corrected post-race without injury', 'injury was recorded in error', '00000000-0000-0000-0000-00000000e712', 2040, 5::smallint, 4::smallint, 2040, 6::smallint, 1::smallint, 'new injury');
    raise exception 'same correction request accepted none-to-injury change' using errcode = 'XX000';
  exception when unique_violation then null;
  end;
  if (select count(*) from public.horse_health_events where replaces_health_event_id = current_setting('test.health.correction_target_id', true)::uuid) <> 1 then
    raise exception 'correction retry wrote a second replacement event';
  end if;
end;
$$;

-- A managed POST_RACE correction with an injury exercises the inverse
-- injury-to-none retry mismatch, injury range/note comparisons, and a manual
-- correction's explicit prohibition on an injury payload.
select public.record_post_race_health(
  '00000000-0000-0000-0000-00000000e719', current_setting('test.health.managed_validation_result_id', true)::uuid,
  70::smallint, 2040, 5::smallint, 4::smallint, 2040, 6::smallint, 1::smallint, 'original correction injury', 'managed source injury'
);
select set_config('test.health.injury_correction_target_id', (
  select id::text from public.horse_health_events where request_id = '00000000-0000-0000-0000-00000000e719'
), true);
select public.correct_latest_horse_health_event(
  current_setting('test.health.injury_correction_target_id', true)::uuid,
  60::smallint, 'corrected managed source injury', 'correct source injury', '00000000-0000-0000-0000-00000000e720',
  2040, 5::smallint, 4::smallint, 2040, 6::smallint, 2::smallint, 'corrected injury note'
);
do $$
declare
  v_manual_event_id uuid;
begin
  perform public.correct_latest_horse_health_event(
    current_setting('test.health.injury_correction_target_id', true)::uuid,
    60::smallint, 'corrected managed source injury', 'correct source injury', '00000000-0000-0000-0000-00000000e720',
    2040, 5::smallint, 4::smallint, 2040, 6::smallint, 2::smallint, 'corrected injury note'
  );
  begin
    perform public.correct_latest_horse_health_event(current_setting('test.health.injury_correction_target_id', true)::uuid, 60::smallint, 'corrected managed source injury', 'correct source injury', '00000000-0000-0000-0000-00000000e720');
    raise exception 'same correction request accepted injury-to-none change' using errcode = 'XX000';
  exception when unique_violation then null;
  end;
  begin
    perform public.correct_latest_horse_health_event(current_setting('test.health.injury_correction_target_id', true)::uuid, 60::smallint, 'corrected managed source injury', 'correct source injury', '00000000-0000-0000-0000-00000000e720', 2040, 5::smallint, 5::smallint, 2040, 6::smallint, 2::smallint, 'corrected injury note');
    raise exception 'same correction request accepted different injury range' using errcode = 'XX000';
  exception when unique_violation then null;
  end;
  begin
    perform public.correct_latest_horse_health_event(current_setting('test.health.injury_correction_target_id', true)::uuid, 60::smallint, 'corrected managed source injury', 'correct source injury', '00000000-0000-0000-0000-00000000e720', 2040, 5::smallint, 4::smallint, 2040, 6::smallint, 2::smallint, 'different injury note');
    raise exception 'same correction request accepted different injury notes' using errcode = 'XX000';
  exception when unique_violation then null;
  end;

  perform public.adjust_horse_stamina('00000000-0000-0000-0000-00000000e627', 70::smallint, 'manual correction payload fixture', '00000000-0000-0000-0000-00000000e721');
  select id into v_manual_event_id from public.horse_health_events where request_id = '00000000-0000-0000-0000-00000000e721';
  begin
    perform public.correct_latest_horse_health_event(v_manual_event_id, 60::smallint, 'manual correction', 'manual cannot create injury', '00000000-0000-0000-0000-00000000e722', 2040, 5::smallint, 4::smallint, 2040, 6::smallint, 1::smallint, 'illegal manual injury');
    raise exception 'manual correction accepted an injury payload' using errcode = 'XX000';
  exception when check_violation then null;
  end;
end;
$$;

-- Explicit manual disable and re-enable preserve historical chain and do not
-- turn zero into unmanaged implicitly.
select public.adjust_horse_stamina('00000000-0000-0000-0000-00000000e621', null, 'stop tracking deliberately', '00000000-0000-0000-0000-00000000e713');
select public.adjust_horse_stamina('00000000-0000-0000-0000-00000000e621', 100::smallint, 're-enable explicitly', '00000000-0000-0000-0000-00000000e714');

-- Manual injuries work independently of stamina, block only through existing
-- ACTIVE injury logic, and RECOVERED no longer blocks scheduling.
select public.create_manual_injury('00000000-0000-0000-0000-00000000e625', 2040, 5::smallint, 4::smallint, 2040, 5::smallint, 5::smallint, 'training injury');
select set_config('test.health.manual_injury_id', (
  select injury.id::text
  from public.injuries as injury
  left join public.injury_private_metadata as metadata on metadata.injury_id = injury.id
  where injury.horse_id = '00000000-0000-0000-0000-00000000e625'
    and injury.notes = 'training injury'
    and metadata.source_health_event_id is null
), true);

do $$
begin
  begin
    perform public.create_gm_confirmed_race_entry('00000000-0000-0000-0000-00000000e625', 2040, 5::smallint, 5::smallint, 'CATALOG'::public.race_entry_race_kind, '00000000-0000-0000-0000-00000000e630', null, null, null, null);
    raise exception 'ACTIVE injury did not block the inclusive end week' using errcode = 'XX000';
  exception when check_violation then null;
  end;
end;
$$;

select public.resolve_injury(current_setting('test.health.manual_injury_id', true)::uuid, 'WP recovery confirmed');
select public.create_gm_confirmed_race_entry('00000000-0000-0000-0000-00000000e625', 2040, 5::smallint, 5::smallint, 'CATALOG'::public.race_entry_race_kind, '00000000-0000-0000-0000-00000000e630', null, null, null, null);

-- Result void is allowed only when its POST_RACE event is latest. It rolls
-- back stamina and voids source injuries in the same transaction.
select public.void_race_result(current_setting('test.health.void_result_id', true)::uuid, 'void latest health result');

-- Normal result correction remains independent of health events.
select public.correct_race_result(current_setting('test.health.unmanaged_result_id', true)::uuid, current_setting('test.health.actual_race_id', true)::uuid, 2::smallint, 100::bigint, null, null, 'prize correction leaves health alone', 'correct prize only');

do $$
declare
  v_old_event uuid;
  v_new_event uuid;
begin
  select id into v_old_event from public.horse_health_events where race_result_id = current_setting('test.health.void_result_id', true)::uuid and status = 'VOIDED' order by event_sequence limit 1;
  select id into v_new_event from public.horse_health_events where race_result_id = current_setting('test.health.void_result_id', true)::uuid and status = 'VOIDED' order by event_sequence desc limit 1;
  if v_old_event is null or v_new_event is null
    or exists (
      select 1
      from public.injuries as injury
      join public.injury_private_metadata as metadata on metadata.injury_id = injury.id
      where metadata.source_health_event_id = v_old_event
        and injury.status <> 'VOIDED'::public.injury_status
    )
    or (select current_stamina from public.horses where id = '00000000-0000-0000-0000-00000000e623') is not null then
    raise exception 'result void did not leave a legal voided-health state';
  end if;
  if not exists (select 1 from public.race_results where id = current_setting('test.health.void_result_id', true)::uuid and status = 'VOIDED')
    or not exists (select 1 from public.prize_receivables where race_result_id = current_setting('test.health.void_result_id', true)::uuid and status = 'CANCELLED') then
    raise exception 'result void did not preserve existing prize-void behavior';
  end if;
  if (select current_stamina from public.horses where id = '00000000-0000-0000-0000-00000000e621') <> 100 then
    raise exception 'manual disable/re-enable did not finish at explicit 100';
  end if;
  if not exists (select 1 from public.horse_health_events where horse_id = '00000000-0000-0000-0000-00000000e621' and event_type = 'MANUAL_ADJUSTMENT'::public.horse_health_event_type and stamina_before = 0 and stamina_after is null and status = 'ACTIVE') then
    raise exception 'manual 0 -> NULL disable event is missing';
  end if;
  if (select count(*) from public.horse_health_events where race_result_id = current_setting('test.health.unmanaged_result_id', true)::uuid and status = 'ACTIVE') <> 1 then
    raise exception 'result correction modified health event facts';
  end if;
  if not exists (select 1 from public.race_results where id = current_setting('test.health.nonlatest_result_id', true)::uuid and status = 'CONFIRMED')
    or not exists (select 1 from public.horse_health_events where race_result_id = current_setting('test.health.nonlatest_result_id', true)::uuid and status = 'ACTIVE') then
    raise exception 'non-latest result void caused a partial state change';
  end if;
end;
$$;

-- Auth account deletion must retain immutable health facts while PostgreSQL
-- clears optional historical actors through the nested FK action. Use separate
-- GM actors so confirmed, voided, and injury-private actor nulling are covered.
reset role;
insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-00000000e603', 'authenticated', 'authenticated', 'health-delete-confirmed@example.test', 'not-used', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-00000000e604', 'authenticated', 'authenticated', 'health-delete-voided@example.test', 'not-used', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now());

insert into public.user_profiles (id, role, owner_id, display_name)
values
  ('00000000-0000-0000-0000-00000000e603', 'GM', null, 'Health Delete Confirmed GM'),
  ('00000000-0000-0000-0000-00000000e604', 'GM', null, 'Health Delete Voided GM');

insert into public.horses (
  id, horse_number, birth_year, foal_name, sex, coat_color,
  sire_name, sire_line, broodmare_sire_name, owner_id, life_stage
) values
  ('00000000-0000-0000-0000-00000000e628', 96108, 2037, 'Auth Delete Confirmed Horse', 'MALE', 'BAY', 'Health Sire H', 'Health Line H', 'Health Dam H', '00000000-0000-0000-0000-00000000e610', 'ACTIVE'),
  ('00000000-0000-0000-0000-00000000e629', 96109, 2037, 'Auth Delete Voided Horse', 'FEMALE', 'BAY', 'Health Sire I', 'Health Line I', 'Health Dam I', '00000000-0000-0000-0000-00000000e610', 'ACTIVE');

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000e603', true);
select set_config('request.jwt.claim.role', 'authenticated', true);

select public.adjust_horse_stamina(
  '00000000-0000-0000-0000-00000000e628', 75::smallint,
  'Auth deletion confirmed actor fixture', '00000000-0000-0000-0000-00000000e730'
);
select set_config('test.health.auth_delete_confirmed_event_id', (
  select id::text from public.horse_health_events
  where request_id = '00000000-0000-0000-0000-00000000e730'
), true);

select public.create_manual_injury(
  '00000000-0000-0000-0000-00000000e628',
  2040, 5::smallint, 4::smallint, 2040, 5::smallint, 5::smallint,
  'Auth deletion private actor fixture'
);
select set_config('test.health.auth_delete_injury_id', (
  select id::text from public.injuries
  where horse_id = '00000000-0000-0000-0000-00000000e628'
    and notes = 'Auth deletion private actor fixture'
), true);
select public.resolve_injury(
  current_setting('test.health.auth_delete_injury_id', true)::uuid,
  'Auth deletion private actor resolution'
);

select public.adjust_horse_stamina(
  '00000000-0000-0000-0000-00000000e629', 50::smallint,
  'Auth deletion voided actor fixture', '00000000-0000-0000-0000-00000000e731'
);
select set_config('test.health.auth_delete_voided_event_id', (
  select id::text from public.horse_health_events
  where request_id = '00000000-0000-0000-0000-00000000e731'
), true);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000e604', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select public.void_latest_horse_health_event(
  current_setting('test.health.auth_delete_voided_event_id', true)::uuid,
  'Auth deletion voided actor reason'
);

reset role;
do $$
declare
  v_confirmed_event_id uuid := current_setting('test.health.auth_delete_confirmed_event_id', true)::uuid;
  v_voided_event_id uuid := current_setting('test.health.auth_delete_voided_event_id', true)::uuid;
  v_injury_id uuid := current_setting('test.health.auth_delete_injury_id', true)::uuid;
  v_confirmed_before jsonb;
  v_confirmed_after jsonb;
  v_voided_before jsonb;
  v_voided_after jsonb;
  v_metadata_before jsonb;
  v_metadata_after jsonb;
begin
  select to_jsonb(health_event) into v_confirmed_before
  from public.horse_health_events as health_event where id = v_confirmed_event_id;
  select to_jsonb(health_event) into v_voided_before
  from public.horse_health_events as health_event where id = v_voided_event_id;
  select to_jsonb(metadata) into v_metadata_before
  from public.injury_private_metadata as metadata where injury_id = v_injury_id;

  if v_confirmed_before ->> 'confirmed_by_user_id' <> '00000000-0000-0000-0000-00000000e603'
    or v_voided_before ->> 'voided_by_user_id' <> '00000000-0000-0000-0000-00000000e604'
    or v_voided_before ->> 'status' <> 'VOIDED'
    or v_voided_before ->> 'voided_at' is null
    or v_voided_before ->> 'void_reason' <> 'Auth deletion voided actor reason'
    or v_metadata_before ->> 'resolved_by_user_id' <> '00000000-0000-0000-0000-00000000e603' then
    raise exception 'Auth deletion fixture did not record the expected historical actors';
  end if;

  delete from auth.users where id = '00000000-0000-0000-0000-00000000e604';

  select to_jsonb(health_event) into v_voided_after
  from public.horse_health_events as health_event where id = v_voided_event_id;
  if v_voided_after ->> 'voided_by_user_id' is not null
    or v_voided_after ->> 'status' <> 'VOIDED'
    or v_voided_after ->> 'voided_at' is distinct from v_voided_before ->> 'voided_at'
    or v_voided_after ->> 'void_reason' is distinct from v_voided_before ->> 'void_reason'
    or (v_voided_before - 'voided_by_user_id' - 'updated_at')
       is distinct from (v_voided_after - 'voided_by_user_id' - 'updated_at') then
    raise exception 'Auth deletion changed immutable voided health-event facts';
  end if;

  delete from auth.users where id = '00000000-0000-0000-0000-00000000e603';

  select to_jsonb(health_event) into v_confirmed_after
  from public.horse_health_events as health_event where id = v_confirmed_event_id;
  select to_jsonb(metadata) into v_metadata_after
  from public.injury_private_metadata as metadata where injury_id = v_injury_id;

  if v_confirmed_after ->> 'confirmed_by_user_id' is not null
    or (v_confirmed_before - 'confirmed_by_user_id' - 'updated_at')
       is distinct from (v_confirmed_after - 'confirmed_by_user_id' - 'updated_at') then
    raise exception 'Auth deletion changed immutable confirmed health-event facts';
  end if;
  if v_metadata_after ->> 'resolved_by_user_id' is not null
    or (v_metadata_before - 'resolved_by_user_id' - 'updated_at')
       is distinct from (v_metadata_after - 'resolved_by_user_id' - 'updated_at') then
    raise exception 'Auth deletion changed injury private metadata beyond the actor';
  end if;

  begin
    update public.horse_health_events
    set confirmed_by_user_id = null
    where id = v_confirmed_event_id;
    raise exception 'ordinary confirmed_by_user_id update was accepted' using errcode = 'XX000';
  exception when object_not_in_prerequisite_state then null;
  end;
  begin
    update public.horse_health_events
    set voided_by_user_id = null
    where id = v_voided_event_id;
    raise exception 'ordinary voided_by_user_id update was accepted' using errcode = 'XX000';
  exception when object_not_in_prerequisite_state then null;
  end;
  begin
    update public.horse_health_events
    set stamina_after = 99::smallint
    where id = v_confirmed_event_id;
    raise exception 'ordinary stamina_after update was accepted' using errcode = 'XX000';
  exception when object_not_in_prerequisite_state then null;
  end;
  begin
    update public.horse_health_events
    set status = 'ACTIVE'::public.horse_health_event_status
    where id = v_voided_event_id;
    raise exception 'ordinary status update was accepted' using errcode = 'XX000';
  exception when object_not_in_prerequisite_state then null;
  end;
end;
$$;

-- PLAYER sees only the safe health projection and cannot mutate health,
-- injury, stamina, or invoke a GM RPC despite the authenticated EXECUTE grant.
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000e601', true);
select set_config('request.jwt.claim.role', 'authenticated', true);

do $$
declare
  v_public jsonb;
  v_updated integer;
begin
  if (select count(*) from public.horse_health_events) <> 0 then
    raise exception 'PLAYER read GM-only horse_health_events base rows';
  end if;
  if (select count(*) from public.injuries) = 0 then
    raise exception 'PLAYER lost legacy injury reads used by existing pages';
  end if;
  if (select count(*) from public.injury_private_metadata) <> 0 then
    raise exception 'PLAYER read private injury source or lifecycle metadata';
  end if;
  begin
    execute 'select source_health_event_id from public.injuries limit 1';
    raise exception 'PLAYER selected a v0.6 private injury column from the legacy table' using errcode = 'XX000';
  exception when undefined_column then null;
  end;
  select to_jsonb(row) into v_public from public.horse_health_events_public row where horse_id = '00000000-0000-0000-0000-00000000e621' limit 1;
  if v_public is null or v_public ? 'notes' or v_public ? 'request_id' or v_public ? 'confirmed_by_user_id' or v_public ? 'void_reason' then
    raise exception 'health public projection is absent or leaks private data';
  end if;
  begin
    perform public.adjust_horse_stamina('00000000-0000-0000-0000-00000000e621', 80::smallint, 'player attack', '00000000-0000-0000-0000-00000000e715');
    raise exception 'PLAYER adjusted stamina' using errcode = 'XX000';
  exception when insufficient_privilege then null;
  end;
  update public.horses set current_stamina = 80 where id = '00000000-0000-0000-0000-00000000e621';
  get diagnostics v_updated = row_count;
  if v_updated <> 0 then raise exception 'PLAYER directly changed stamina'; end if;
  begin
    insert into public.injuries (horse_id, status, wp_start_year, wp_start_month, wp_start_week, wp_end_year, wp_end_month, wp_end_week)
    values ('00000000-0000-0000-0000-00000000e621', 'ACTIVE', 2040, 6, 1, 2040, 6, 2);
    raise exception 'PLAYER directly created an injury' using errcode = 'XX000';
  exception when insufficient_privilege then null;
  end;
end;
$$;

reset role;
set local role anon;
do $$ begin
  begin
    perform public.record_post_race_health('00000000-0000-0000-0000-00000000e716', current_setting('test.health.unmanaged_result_id', true)::uuid, null, null, null, null, null, null, null, null, null);
    raise exception 'anon called post-race health RPC' using errcode = 'XX000';
  exception when insufficient_privilege then null;
  end;
end $$;

reset role;
set local role service_role;
do $$ begin
  begin
    perform public.adjust_horse_stamina('00000000-0000-0000-0000-00000000e621', 80::smallint, 'service role attack', '00000000-0000-0000-0000-00000000e717');
    raise exception 'service_role called stamina RPC despite ACL' using errcode = 'XX000';
  exception when insufficient_privilege then null;
  end;
end $$;

reset role;
rollback;
