-- Local SQL verification for HorseRPG v0.4-C Race Results.
-- Run after `npx supabase db reset`. All test rows are rolled back.

begin;

do $$
declare
  v_function text;
begin
  if not exists (
    select 1 from pg_type where typname = 'race_result_status' and typnamespace = 'public'::regnamespace
  ) then
    raise exception 'race_result_status enum is missing';
  end if;

  if not exists (
    select 1 from pg_tables where schemaname = 'public' and tablename = 'actual_races'
  ) or not exists (
    select 1 from pg_tables where schemaname = 'public' and tablename = 'race_results'
  ) or not exists (
    select 1 from pg_views where schemaname = 'public' and viewname = 'race_results_public'
  ) then
    raise exception 'Race Results tables or public view are missing';
  end if;

  if not (
    select relrowsecurity from pg_class where oid = 'public.actual_races'::regclass
  ) or not (
    select relrowsecurity from pg_class where oid = 'public.race_results'::regclass
  ) then
    raise exception 'Race Results base tables do not enable RLS';
  end if;

  if not exists (
    select 1 from pg_indexes where schemaname = 'public' and indexname = 'actual_races_one_catalog_per_wp_week_idx'
  ) or not exists (
    select 1 from pg_indexes where schemaname = 'public' and indexname = 'race_results_one_confirmed_result_per_entry_idx'
  ) or not exists (
    select 1 from pg_indexes where schemaname = 'public' and indexname = 'race_results_one_confirmed_result_per_horse_actual_race_idx'
  ) then
    raise exception 'Race Results partial unique index is missing';
  end if;

  foreach v_function in array array[
    'public.create_actual_race(integer,smallint,smallint,public.race_entry_race_kind,uuid,text)'::text,
    'public.correct_actual_race(uuid,integer,smallint,smallint,public.race_entry_race_kind,uuid,text,text)'::text,
    'public.record_race_result(uuid,uuid,smallint,bigint,text,text,text)'::text,
    'public.correct_race_result(uuid,uuid,smallint,bigint,text,text,text,text)'::text,
    'public.void_race_result(uuid,text)'::text
  ] loop
    if not exists (
      select 1 from pg_proc as procedure
      where procedure.oid = v_function::regprocedure
        and procedure.prosecdef
        and procedure.proconfig is not null
        and procedure.proconfig::text like '%search_path=%'
    ) then
      raise exception 'Race Results RPC is missing, not SECURITY DEFINER, or has no fixed search path: %', v_function;
    end if;

    if has_function_privilege('public', v_function::regprocedure, 'EXECUTE')
      or has_function_privilege('anon', v_function::regprocedure, 'EXECUTE')
      or has_function_privilege('service_role', v_function::regprocedure, 'EXECUTE')
      or not has_function_privilege('authenticated', v_function::regprocedure, 'EXECUTE') then
      raise exception 'Race Results RPC has an incorrect EXECUTE ACL: %', v_function;
    end if;
  end loop;

  foreach v_function in array array[
    'public.enforce_race_result_entry_integrity()'::text,
    'public.assert_actual_race_wp_time_not_future(integer,smallint,smallint)'::text,
    'public.resolve_actual_race_identity(public.race_entry_race_kind,uuid,text)'::text,
    'public.actual_race_audit_data(public.actual_races)'::text,
    'public.race_result_audit_data(public.race_results)'::text,
    'public.assert_race_result_facts(smallint,bigint)'::text
  ] loop
    if has_function_privilege('public', v_function::regprocedure, 'EXECUTE')
      or has_function_privilege('anon', v_function::regprocedure, 'EXECUTE')
      or has_function_privilege('authenticated', v_function::regprocedure, 'EXECUTE')
      or has_function_privilege('service_role', v_function::regprocedure, 'EXECUTE') then
      raise exception 'Race Results helper has a client EXECUTE ACL: %', v_function;
    end if;
  end loop;

  if has_table_privilege('public', 'public.race_results_public', 'SELECT')
    or has_table_privilege('anon', 'public.race_results_public', 'SELECT')
    or not has_table_privilege('authenticated', 'public.race_results_public', 'SELECT')
    or has_table_privilege('authenticated', 'public.race_results_public', 'INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER') then
    raise exception 'race_results_public has an incorrect ACL';
  end if;

  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'race_results_public'
      and column_name in ('gm_note', 'recorded_by_user_id', 'voided_by_user_id', 'void_reason')
  ) then
    raise exception 'race_results_public exposes a GM-private column';
  end if;
end;
$$;

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
values
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-00000000d101', 'authenticated', 'authenticated', 'results-player-a@example.test', 'not-used', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-00000000d102', 'authenticated', 'authenticated', 'results-player-b@example.test', 'not-used', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-00000000d103', 'authenticated', 'authenticated', 'results-gm@example.test', 'not-used', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now());

insert into public.owners (id, display_name, initial_funds)
values
  ('00000000-0000-0000-0000-00000000d201', 'Results Owner A', 100000000),
  ('00000000-0000-0000-0000-00000000d202', 'Results Owner B', 100000000);

insert into public.user_profiles (id, role, owner_id, display_name)
values
  ('00000000-0000-0000-0000-00000000d101', 'PLAYER', '00000000-0000-0000-0000-00000000d201', 'Results Player A'),
  ('00000000-0000-0000-0000-00000000d102', 'PLAYER', '00000000-0000-0000-0000-00000000d202', 'Results Player B'),
  ('00000000-0000-0000-0000-00000000d103', 'GM', null, 'Results GM');

insert into public.game_state (id, current_wp_year, current_wp_month, current_wp_week, updated_by_user_id)
values (true, 2035, 5, 4, '00000000-0000-0000-0000-00000000d103');

insert into public.horses (
  id, horse_number, birth_year, foal_name, sex, coat_color,
  sire_name, sire_line, broodmare_sire_name, owner_id, life_stage
)
values
  ('00000000-0000-0000-0000-00000000d301', 84101, 2032, 'Results Request Horse', 'MALE', 'BAY', 'Results Sire A', 'Results Line A', 'Results Dam A', '00000000-0000-0000-0000-00000000d201', 'ACTIVE'),
  ('00000000-0000-0000-0000-00000000d302', 84102, 2032, 'Results Direct Horse', 'FEMALE', 'CHESTNUT', 'Results Sire B', 'Results Line B', 'Results Dam B', '00000000-0000-0000-0000-00000000d202', 'ACTIVE'),
  ('00000000-0000-0000-0000-00000000d303', 84103, 2032, 'Results Invalid Horse', 'MALE', 'BROWN', 'Results Sire C', 'Results Line C', 'Results Dam C', '00000000-0000-0000-0000-00000000d201', 'ACTIVE');

insert into public.race_catalog (id, name, grade, default_wp_month, default_wp_week, is_active)
values
  ('00000000-0000-0000-0000-00000000d401', 'Results Catalog G1', 'G1', 5, 4, true),
  ('00000000-0000-0000-0000-00000000d402', 'Results Catalog G2', 'G2', 5, 4, true),
  ('00000000-0000-0000-0000-00000000d403', 'Results Historical OP', 'OP', 4, 4, false);

-- Establish both a request-backed confirmed entry and GM direct entries.
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000d101', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select public.submit_race_entry_request(
  '00000000-0000-0000-0000-00000000d301', 2035, 5::smallint, 5::smallint,
  'CATALOG'::public.race_entry_race_kind, '00000000-0000-0000-0000-00000000d402', null, null, null, 'result source request'
);
select set_config('test.results.request_id', (
  select id::text from public.race_entry_requests where player_note = 'result source request'
), true);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000d103', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select public.confirm_race_entry_request(
  current_setting('test.results.request_id', true)::uuid,
  2035, 5::smallint, 5::smallint,
  'CATALOG'::public.race_entry_race_kind, '00000000-0000-0000-0000-00000000d402', null, null, null, null
);
select set_config('test.results.request_entry_id', (
  select id::text from public.confirmed_race_entries where request_id = current_setting('test.results.request_id', true)::uuid
), true);

select public.create_gm_confirmed_race_entry(
  '00000000-0000-0000-0000-00000000d302', 2035, 5::smallint, 5::smallint,
  'CATALOG'::public.race_entry_race_kind, '00000000-0000-0000-0000-00000000d402', null, null, null, null
);
select set_config('test.results.direct_entry_id', (
  select id::text from public.confirmed_race_entries where horse_id = '00000000-0000-0000-0000-00000000d302'
), true);

select public.create_gm_confirmed_race_entry(
  '00000000-0000-0000-0000-00000000d301', 2035, 6::smallint, 1::smallint,
  'CATALOG'::public.race_entry_race_kind, '00000000-0000-0000-0000-00000000d402', null, null, null, null
);
select set_config('test.results.second_entry_same_horse_id', (
  select id::text from public.confirmed_race_entries
  where horse_id = '00000000-0000-0000-0000-00000000d301' and request_id is null
), true);

select public.create_gm_confirmed_race_entry(
  '00000000-0000-0000-0000-00000000d303', 2035, 5::smallint, 5::smallint,
  'CATALOG'::public.race_entry_race_kind, '00000000-0000-0000-0000-00000000d402', null, null, null, null
);
select set_config('test.results.invalid_entry_id', (
  select id::text from public.confirmed_race_entries where horse_id = '00000000-0000-0000-0000-00000000d303'
), true);

-- CATALOG Actual Race snapshots the currently selected catalog. Current and
-- past dates work; future dates and ambiguous identities do not.
select public.create_actual_race(
  2035, 5::smallint, 4::smallint,
  'CATALOG'::public.race_entry_race_kind, '00000000-0000-0000-0000-00000000d401', null
);
select set_config('test.results.catalog_actual_id', (
  select id::text from public.actual_races
  where race_kind = 'CATALOG'::public.race_entry_race_kind and race_catalog_id = '00000000-0000-0000-0000-00000000d401'
    and (wp_year, wp_month, wp_week) = (2035, 5, 4)
), true);

do $$
begin
  if not exists (
    select 1 from public.actual_races
    where id = current_setting('test.results.catalog_actual_id', true)::uuid
      and race_name = 'Results Catalog G1'
      and grade = 'G1'::public.race_catalog_grade
  ) then
    raise exception 'catalog actual race did not snapshot catalog name and grade';
  end if;

  begin
    perform public.create_actual_race(2035, 5::smallint, 4::smallint, 'CATALOG'::public.race_entry_race_kind, '00000000-0000-0000-0000-00000000d401', null);
    raise exception 'duplicate CATALOG actual race was accepted' using errcode = 'XX000';
  exception when unique_violation then null;
  end;

  begin
    perform public.create_actual_race(2035, 5::smallint, 5::smallint, 'CATALOG'::public.race_entry_race_kind, null, null);
    raise exception 'catalog actual race without a catalog was accepted' using errcode = 'XX000';
  exception when check_violation then null;
  end;

  begin
    perform public.create_actual_race(2035, 5::smallint, 5::smallint, 'MAIDEN'::public.race_entry_race_kind, null, null);
    raise exception 'non-catalog actual race without a label was accepted' using errcode = 'XX000';
  exception when check_violation then null;
  end;

  begin
    perform public.create_actual_race(2035, 6::smallint, 1::smallint, 'MAIDEN'::public.race_entry_race_kind, null, 'future maiden');
    raise exception 'future actual race was accepted' using errcode = 'XX000';
  exception when check_violation then null;
  end;
end;
$$;

update public.race_catalog
set name = 'Results Catalog G1 Renamed', is_active = false
where id = '00000000-0000-0000-0000-00000000d401';

select public.create_actual_race(
  2035, 5::smallint, 3::smallint,
  'CATALOG'::public.race_entry_race_kind, '00000000-0000-0000-0000-00000000d401', null
);
select public.create_actual_race(
  2035, 5::smallint, 3::smallint,
  'MAIDEN'::public.race_entry_race_kind, null, '3岁未胜利'
);
select public.create_actual_race(
  2035, 5::smallint, 2::smallint,
  'CONDITION'::public.race_entry_race_kind, null, '1胜 Class'
);
select public.create_actual_race(
  2035, 5::smallint, 4::smallint,
  'CATALOG'::public.race_entry_race_kind, '00000000-0000-0000-0000-00000000d402', null
);
select set_config('test.results.main_actual_id', (
  select id::text from public.actual_races
  where race_catalog_id = '00000000-0000-0000-0000-00000000d402' and (wp_year, wp_month, wp_week) = (2035, 5, 4)
), true);
select set_config('test.results.alt_actual_id', (
  select id::text from public.actual_races
  where race_kind = 'CONDITION'::public.race_entry_race_kind and race_name = '1胜 Class'
), true);

do $$
begin
  if not exists (
    select 1 from public.actual_races
    where id = current_setting('test.results.catalog_actual_id', true)::uuid
      and race_name = 'Results Catalog G1'
      and grade = 'G1'::public.race_catalog_grade
  ) then
    raise exception 'later catalog changes rewrote the original actual-race snapshot';
  end if;

  if not exists (
    select 1 from public.actual_races
    where race_catalog_id = '00000000-0000-0000-0000-00000000d401'
      and (wp_year, wp_month, wp_week) = (2035, 5, 3)
      and race_name = 'Results Catalog G1 Renamed'
      and grade = 'G1'::public.race_catalog_grade
  ) then
    raise exception 'an inactive catalog could not be used for a historical actual race snapshot';
  end if;

  if not exists (
    select 1 from public.actual_races
    where race_kind = 'MAIDEN'::public.race_entry_race_kind and race_name = '3岁未胜利' and grade is null and race_catalog_id is null
  ) or not exists (
    select 1 from public.actual_races
    where race_kind = 'CONDITION'::public.race_entry_race_kind and race_name = '1胜 Class' and grade is null and race_catalog_id is null
  ) then
    raise exception 'non-catalog actual race identity is incorrect';
  end if;
end;
$$;

-- Actual-race correction requires a reason, refreshes catalog snapshots, and
-- may move to a non-catalog identity but may never move to a future date.
do $$
begin
  begin
    perform public.correct_actual_race(
      current_setting('test.results.catalog_actual_id', true)::uuid,
      2035, 5::smallint, 2::smallint, 'CATALOG'::public.race_entry_race_kind,
      '00000000-0000-0000-0000-00000000d402', null, ''
    );
    raise exception 'actual-race correction without a reason was accepted' using errcode = 'XX000';
  exception when check_violation then null;
  end;
end;
$$;

select public.correct_actual_race(
  current_setting('test.results.catalog_actual_id', true)::uuid,
  2035, 5::smallint, 2::smallint, 'CATALOG'::public.race_entry_race_kind,
  '00000000-0000-0000-0000-00000000d402', null, 'correct catalog identity'
);
select public.correct_actual_race(
  current_setting('test.results.catalog_actual_id', true)::uuid,
  2035, 5::smallint, 2::smallint, 'MAIDEN'::public.race_entry_race_kind,
  null, '更正后未胜利赛', 'correct to free-text identity'
);

do $$
begin
  if not exists (
    select 1 from public.actual_races
    where id = current_setting('test.results.catalog_actual_id', true)::uuid
      and race_kind = 'MAIDEN'::public.race_entry_race_kind
      and race_name = '更正后未胜利赛'
      and race_catalog_id is null
      and grade is null
  ) then
    raise exception 'actual-race correction did not refresh its snapshot identity';
  end if;

  if not exists (
    select 1 from public.audit_logs
    where action = 'ACTUAL_RACE_CORRECTED'
      and entity_id = current_setting('test.results.catalog_actual_id', true)
      and reason = 'correct to free-text identity'
      and before_data ? 'race_name'
      and after_data ->> 'race_name' = '更正后未胜利赛'
  ) then
    raise exception 'actual-race correction audit is incomplete';
  end if;

  begin
    perform public.correct_actual_race(
      current_setting('test.results.catalog_actual_id', true)::uuid,
      2035, 6::smallint, 1::smallint, 'MAIDEN'::public.race_entry_race_kind,
      null, 'future correction', 'must reject future race'
    );
    raise exception 'actual-race correction to a future week was accepted' using errcode = 'XX000';
  exception when check_violation then null;
  end;
end;
$$;

select set_config('test.results.financial_count_before', (select count(*)::text from public.financial_transactions), true);

-- Request-backed entry: minimal Result and immediate exact retry.
select public.record_race_result(
  current_setting('test.results.request_entry_id', true)::uuid,
  current_setting('test.results.main_actual_id', true)::uuid,
  1::smallint, 0::bigint, null, null, null
);
select set_config('test.results.request_result_id', (
  select id::text from public.race_results
  where confirmed_race_entry_id = current_setting('test.results.request_entry_id', true)::uuid
    and status = 'CONFIRMED'::public.race_result_status
), true);

do $$
declare
  v_retry_id uuid;
begin
  select id into v_retry_id from public.record_race_result(
    current_setting('test.results.request_entry_id', true)::uuid,
    current_setting('test.results.main_actual_id', true)::uuid,
    1::smallint, 0::bigint, null, null, null
  );

  if v_retry_id <> current_setting('test.results.request_result_id', true)::uuid
    or (select count(*) from public.race_results where confirmed_race_entry_id = current_setting('test.results.request_entry_id', true)::uuid and status = 'CONFIRMED'::public.race_result_status) <> 1 then
    raise exception 'identical race-result retry was not idempotent';
  end if;
end;
$$;

-- Once a Result exists, an exact retry or a differing-facts conflict must not
-- be pre-empted by a later correction that makes the Actual Race future.
update public.game_state
set current_wp_week = 3::smallint
where id = true;

do $$
declare
  v_retry_id uuid;
begin
  select id into v_retry_id from public.record_race_result(
    current_setting('test.results.request_entry_id', true)::uuid,
    current_setting('test.results.main_actual_id', true)::uuid,
    1::smallint, 0::bigint, null, null, null
  );

  if v_retry_id <> current_setting('test.results.request_result_id', true)::uuid
    or (select count(*) from public.race_results where confirmed_race_entry_id = current_setting('test.results.request_entry_id', true)::uuid and status = 'CONFIRMED'::public.race_result_status) <> 1 then
    raise exception 'future-state identical race-result retry was not idempotent';
  end if;

  begin
    perform public.record_race_result(
      current_setting('test.results.request_entry_id', true)::uuid,
      current_setting('test.results.main_actual_id', true)::uuid,
      1::smallint, 1::bigint, null, null, null
    );
    raise exception 'different-prize duplicate race result was accepted' using errcode = 'XX000';
  exception when raise_exception then
    if sqlerrm not like '%use correction flow%' then raise; end if;
  end;

  begin
    perform public.record_race_result(
      current_setting('test.results.request_entry_id', true)::uuid,
      current_setting('test.results.main_actual_id', true)::uuid,
      2::smallint, 0::bigint, null, null, null
    );
    raise exception 'different-position duplicate race result was accepted' using errcode = 'XX000';
  exception when raise_exception then
    if sqlerrm not like '%use correction flow%' then raise; end if;
  end;

  begin
    perform public.record_race_result(
      current_setting('test.results.invalid_entry_id', true)::uuid,
      current_setting('test.results.main_actual_id', true)::uuid,
      1::smallint, 0::bigint, null, null, null
    );
    raise exception 'a new result accepted an Actual Race made future by game-state rollback' using errcode = 'XX000';
  exception when others then
    if sqlstate <> '23514'
      or sqlerrm not like '%actual-race WP time cannot be later than the current game week%' then
      raise;
    end if;
  end;
end;
$$;

update public.game_state
set current_wp_week = 4::smallint
where id = true;

-- GM direct entry works equally and two different Horses can share one Actual
-- Race. The minimal nullable actual jockey/style/note remains legal.
select public.record_race_result(
  current_setting('test.results.direct_entry_id', true)::uuid,
  current_setting('test.results.main_actual_id', true)::uuid,
  4::smallint, 5000000::bigint, null, null, null
);

do $$
begin
  if (select count(*) from public.race_results
      where actual_race_id = current_setting('test.results.main_actual_id', true)::uuid
        and status = 'CONFIRMED'::public.race_result_status) <> 2 then
    raise exception 'two Horses could not share one actual race';
  end if;

  begin
    perform public.record_race_result(
      current_setting('test.results.second_entry_same_horse_id', true)::uuid,
      current_setting('test.results.main_actual_id', true)::uuid,
      8::smallint, 0::bigint, null, null, null
    );
    raise exception 'the same Horse received two confirmed results in one actual race' using errcode = 'XX000';
  exception when unique_violation then null;
  end;

  begin
    perform public.record_race_result(
      current_setting('test.results.invalid_entry_id', true)::uuid,
      current_setting('test.results.main_actual_id', true)::uuid,
      1::smallint, -1::bigint, null, null, null
    );
    raise exception 'negative result prize was accepted' using errcode = 'XX000';
  exception when check_violation then null;
  end;

  begin
    perform public.record_race_result(
      current_setting('test.results.invalid_entry_id', true)::uuid,
      current_setting('test.results.main_actual_id', true)::uuid,
      0::smallint, 0::bigint, null, null, null
    );
    raise exception 'zero finish position was accepted' using errcode = 'XX000';
  exception when check_violation then null;
  end;
end;
$$;

-- Only the controlled correction path can change result facts. It records a
-- complete before/after audit while retaining entry and Horse identity.
do $$
begin
  begin
    perform public.correct_race_result(
      current_setting('test.results.request_result_id', true)::uuid,
      current_setting('test.results.alt_actual_id', true)::uuid,
      2::smallint, 2500000::bigint, '实际骑手甲', '差', 'changed after WP', ''
    );
    raise exception 'race-result correction without a reason was accepted' using errcode = 'XX000';
  exception when check_violation then null;
  end;
end;
$$;

select public.correct_race_result(
  current_setting('test.results.request_result_id', true)::uuid,
  current_setting('test.results.alt_actual_id', true)::uuid,
  2::smallint, 2500000::bigint, '实际骑手甲', '差', 'changed after WP', 'correct WP result'
);

do $$
begin
  if not exists (
    select 1 from public.race_results
    where id = current_setting('test.results.request_result_id', true)::uuid
      and confirmed_race_entry_id = current_setting('test.results.request_entry_id', true)::uuid
      and horse_id = '00000000-0000-0000-0000-00000000d301'
      and actual_race_id = current_setting('test.results.alt_actual_id', true)::uuid
      and finish_position = 2 and prize_amount = 2500000
      and actual_jockey = '实际骑手甲' and actual_running_style = '差'
  ) then
    raise exception 'race-result correction did not store the requested final facts';
  end if;

  if not exists (
    select 1 from public.audit_logs
    where action = 'RACE_RESULT_CORRECTED'
      and entity_id = current_setting('test.results.request_result_id', true)
      and reason = 'correct WP result'
      and before_data ->> 'actual_race_id' = current_setting('test.results.main_actual_id', true)
      and after_data ->> 'actual_race_id' = current_setting('test.results.alt_actual_id', true)
      and before_data ->> 'finish_position' = '1'
      and after_data ->> 'finish_position' = '2'
  ) then
    raise exception 'race-result correction audit is incomplete';
  end if;
end;
$$;

-- Voiding preserves the row, hides it from the public view, is idempotent for
-- the same reason, and permits a new current result for the original entry.
select public.void_race_result(
  current_setting('test.results.request_result_id', true)::uuid, 'wrong result bound to actual race'
);
select public.void_race_result(
  current_setting('test.results.request_result_id', true)::uuid, 'wrong result bound to actual race'
);

do $$
begin
  if not exists (
    select 1 from public.race_results
    where id = current_setting('test.results.request_result_id', true)::uuid
      and status = 'VOIDED'::public.race_result_status
      and void_reason = 'wrong result bound to actual race'
      and voided_at is not null
  ) then
    raise exception 'void did not preserve the historical result';
  end if;

  if (select count(*) from public.audit_logs
      where action = 'RACE_RESULT_VOIDED'
        and entity_id = current_setting('test.results.request_result_id', true)) <> 1 then
    raise exception 'repeat void wrote a duplicate audit row';
  end if;

  begin
    perform public.void_race_result(
      current_setting('test.results.request_result_id', true)::uuid, 'different reason'
    );
    raise exception 'voided result reason was overwritten' using errcode = 'XX000';
  exception when check_violation then null;
  end;
end;
$$;

select public.record_race_result(
  current_setting('test.results.request_entry_id', true)::uuid,
  current_setting('test.results.main_actual_id', true)::uuid,
  1::smallint, 0::bigint, null, null, null
);
select set_config('test.results.re_recorded_result_id', (
  select id::text from public.race_results
  where confirmed_race_entry_id = current_setting('test.results.request_entry_id', true)::uuid
    and status = 'CONFIRMED'::public.race_result_status
), true);

do $$
begin
  if current_setting('test.results.re_recorded_result_id', true)::uuid = current_setting('test.results.request_result_id', true)::uuid
    or (select count(*) from public.race_results where confirmed_race_entry_id = current_setting('test.results.request_entry_id', true)::uuid) <> 2 then
    raise exception 'voided result was not replaced by a distinct confirmed result';
  end if;

  if (select count(*) from public.financial_transactions) <> current_setting('test.results.financial_count_before', true)::integer then
    raise exception 'race-result record, correction, or void changed the financial ledger';
  end if;

  if (select count(*) from public.actual_races) = 0
    or (select count(*) from public.race_results) = 0 then
    raise exception 'GM could not read a Race Results base table under RLS';
  end if;
end;
$$;

-- PLAYER has only the public projection. The base tables stay GM-only and
-- neither the view shape nor rows disclose private note / actor / void facts.
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000d101', true);
select set_config('request.jwt.claim.role', 'authenticated', true);

do $$
declare
  v_public jsonb;
begin
  if (select count(*) from public.actual_races) <> 0
    or (select count(*) from public.race_results) <> 0 then
    raise exception 'PLAYER read a GM-only Race Results base row';
  end if;

  select to_jsonb(public_row)
  into v_public
  from public.race_results_public as public_row
  where race_result_id = current_setting('test.results.re_recorded_result_id', true)::uuid;

  if v_public is null
    or v_public ? 'gm_note'
    or v_public ? 'recorded_by_user_id'
    or v_public ? 'voided_by_user_id'
    or v_public ? 'void_reason'
    or v_public ->> 'owner_id' <> '00000000-0000-0000-0000-00000000d201' then
    raise exception 'public Race Result projection is missing a public fact or leaks a private fact';
  end if;

  if exists (
    select 1 from public.race_results_public
    where race_result_id = current_setting('test.results.request_result_id', true)::uuid
  ) then
    raise exception 'public Race Result projection exposed a VOIDED result';
  end if;

  begin
    perform public.record_race_result(
      current_setting('test.results.request_entry_id', true)::uuid,
      current_setting('test.results.main_actual_id', true)::uuid,
      1::smallint, 0::bigint, null, null, null
    );
    raise exception 'PLAYER recorded a race result' using errcode = 'XX000';
  exception when insufficient_privilege then null;
  end;
end;
$$;

reset role;
set local role anon;
do $$
begin
  begin
    perform public.record_race_result(
      current_setting('test.results.request_entry_id', true)::uuid,
      current_setting('test.results.main_actual_id', true)::uuid,
      1::smallint, 0::bigint, null, null, null
    );
    raise exception 'anon called record_race_result' using errcode = 'XX000';
  exception when insufficient_privilege then null;
  end;
end;
$$;

reset role;
set local role service_role;
do $$
begin
  begin
    perform public.record_race_result(
      current_setting('test.results.request_entry_id', true)::uuid,
      current_setting('test.results.main_actual_id', true)::uuid,
      1::smallint, 0::bigint, null, null, null
    );
    raise exception 'service_role called record_race_result despite ACL' using errcode = 'XX000';
  exception when insufficient_privilege then null;
  end;
end;
$$;

-- Auth deletion retains historical actual race, result, and audit facts while
-- FK actor fields become NULL. The append-only audit trigger must permit it.
reset role;
delete from auth.users where id = '00000000-0000-0000-0000-00000000d103';

do $$
begin
  if (select count(*) from public.actual_races) = 0
    or (select count(*) from public.race_results) = 0
    or not exists (
      select 1 from public.actual_races where created_by_user_id is null
    )
    or not exists (
      select 1 from public.race_results where recorded_by_user_id is null
    )
    or not exists (
      select 1 from public.race_results where status = 'VOIDED'::public.race_result_status and voided_by_user_id is null
    )
    or not exists (
      select 1 from public.audit_logs
      where action in ('ACTUAL_RACE_CREATED', 'RACE_RESULT_RECORDED', 'RACE_RESULT_CORRECTED', 'RACE_RESULT_VOIDED')
        and actor_user_id is null
    ) then
    raise exception 'Auth deletion did not preserve Race Results history with nullable actor references';
  end if;
end;
$$;

rollback;
