-- Local-only verification for the v0.4-A Race Management migration.
-- Run after `npx supabase db reset`; all fixtures are rolled back.

begin;

do $$
declare
  v_function regprocedure;
begin
  if exists (
    select 1
    from pg_class as relation
    join pg_namespace as namespace on namespace.oid = relation.relnamespace
    where namespace.nspname = 'public'
      and relation.relname in ('race_catalog', 'race_entry_requests', 'confirmed_race_entries')
      and not relation.relrowsecurity
  ) then
    raise exception 'one or more Race Management tables do not enable RLS';
  end if;

  foreach v_function in array array[
    'public.submit_race_entry_request(uuid,integer,smallint,smallint,public.race_entry_race_kind,uuid,text,text,text,text)'::regprocedure,
    'public.withdraw_race_entry_request(uuid)'::regprocedure,
    'public.confirm_race_entry_request(uuid,integer,smallint,smallint,public.race_entry_race_kind,uuid,text,text,text,text)'::regprocedure,
    'public.create_gm_confirmed_race_entry(uuid,integer,smallint,smallint,public.race_entry_race_kind,uuid,text,text,text,text)'::regprocedure,
    'public.reject_race_entry_request(uuid,text)'::regprocedure
  ]
  loop
    if not exists (
      select 1
      from pg_proc as procedure
      where procedure.oid = v_function
        and procedure.prosecdef
        and 'search_path=""' = any(coalesce(procedure.proconfig, array[]::text[]))
    ) then
      raise exception 'Race Management RPC % lacks SECURITY DEFINER or fixed search_path', v_function;
    end if;

    if not has_function_privilege('authenticated', v_function, 'EXECUTE')
      or has_function_privilege('anon', v_function, 'EXECUTE')
      or has_function_privilege('service_role', v_function, 'EXECUTE')
      or exists (
        select 1
        from pg_proc as procedure
        cross join lateral aclexplode(coalesce(procedure.proacl, acldefault('f', procedure.proowner))) as acl
        where procedure.oid = v_function
          and acl.grantee = 0
          and acl.privilege_type = 'EXECUTE'
      ) then
      raise exception 'Race Management RPC % ACL is incorrect', v_function;
    end if;
  end loop;

  if has_function_privilege('authenticated', 'public.assert_race_entry_wp_time_not_past(integer,smallint,smallint)'::regprocedure, 'EXECUTE')
    or has_function_privilege('authenticated', 'public.assert_race_entry_identity(public.race_entry_race_kind,uuid,text)'::regprocedure, 'EXECUTE')
    or has_function_privilege('authenticated', 'public.validate_confirmed_race_entry(uuid,uuid,integer,smallint,smallint,public.race_entry_race_kind,uuid,text)'::regprocedure, 'EXECUTE')
    or has_function_privilege('authenticated', 'public.enforce_confirmed_race_entry_request_integrity()'::regprocedure, 'EXECUTE')
    or has_function_privilege('authenticated', 'public.enforce_race_entry_request_resolution_integrity()'::regprocedure, 'EXECUTE') then
    raise exception 'Race Management helper function is client-callable';
  end if;

  if has_table_privilege('anon', 'public.race_catalog', 'SELECT')
    or has_table_privilege('authenticated', 'public.race_entry_requests', 'INSERT, UPDATE, DELETE')
    or has_table_privilege('authenticated', 'public.confirmed_race_entries', 'INSERT, UPDATE, DELETE')
    or not has_table_privilege('authenticated', 'public.race_catalog', 'SELECT')
    or not has_table_privilege('authenticated', 'public.confirmed_race_entries', 'SELECT')
    or has_table_privilege('anon', 'public.confirmed_race_entries_public', 'SELECT')
    or not has_table_privilege('authenticated', 'public.confirmed_race_entries_public', 'SELECT')
    or has_table_privilege('authenticated', 'public.confirmed_race_entries_public', 'INSERT, UPDATE, DELETE')
    or not exists (
      select 1
      from pg_class as relation
      join pg_namespace as namespace on namespace.oid = relation.relnamespace
      where namespace.nspname = 'public'
        and relation.relname = 'confirmed_race_entries_public'
        and relation.relkind = 'v'
    )
    or exists (
      select 1
      from information_schema.columns
      where table_schema = 'public'
        and table_name = 'confirmed_race_entries_public'
        and column_name in ('request_id', 'gm_note', 'confirmed_by_user_id')
    ) then
    raise exception 'Race Management table ACL is incorrect';
  end if;
end;
$$;

set local role anon;
do $$
begin
  begin
    perform 1 from public.race_catalog;
    raise exception 'anon read Race Catalog' using errcode = 'XX000';
  exception when insufficient_privilege then null;
  end;

  begin
    perform public.submit_race_entry_request(
      '00000000-0000-0000-0000-000000004301', 2030, 4::smallint, 2::smallint,
      'CATALOG'::public.race_entry_race_kind, '00000000-0000-0000-0000-000000004401', null, null, null, null
    );
    raise exception 'anon invoked the PLAYER race-request RPC' using errcode = 'XX000';
  exception when insufficient_privilege then null;
  end;

  begin
    perform public.create_gm_confirmed_race_entry(
      '00000000-0000-0000-0000-000000004301', 2030, 4::smallint, 2::smallint,
      'CATALOG'::public.race_entry_race_kind, '00000000-0000-0000-0000-000000004401', null, null, null, null
    );
    raise exception 'anon invoked the GM direct race-entry RPC' using errcode = 'XX000';
  exception when insufficient_privilege then null;
  end;
end;
$$;
reset role;

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
values
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000004201', 'authenticated', 'authenticated', 'race-player-a@example.test', 'not-used', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000004202', 'authenticated', 'authenticated', 'race-player-b@example.test', 'not-used', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000004203', 'authenticated', 'authenticated', 'race-gm@example.test', 'not-used', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now());

insert into public.owners (id, display_name, initial_funds)
values
  ('00000000-0000-0000-0000-000000004101', 'Race Owner A', 100000000),
  ('00000000-0000-0000-0000-000000004102', 'Race Owner B', 100000000);

insert into public.user_profiles (id, role, owner_id, display_name)
values
  ('00000000-0000-0000-0000-000000004201', 'PLAYER', '00000000-0000-0000-0000-000000004101', 'Race Player A'),
  ('00000000-0000-0000-0000-000000004202', 'PLAYER', '00000000-0000-0000-0000-000000004102', 'Race Player B'),
  ('00000000-0000-0000-0000-000000004203', 'GM', null, 'Race GM');

insert into public.game_state (id, current_wp_year, current_wp_month, current_wp_week, updated_by_user_id)
values (true, 2030, 4, 1, '00000000-0000-0000-0000-000000004203');

insert into public.horses (
  id, horse_number, birth_year, foal_name, sex, coat_color,
  sire_name, sire_line, broodmare_sire_name, owner_id, life_stage
)
values
  ('00000000-0000-0000-0000-000000004301', 64001, 2027, 'Race Active A', 'MALE', 'BAY', 'Race Sire A', 'Race Line A', 'Race Dam A', '00000000-0000-0000-0000-000000004101', 'ACTIVE'),
  ('00000000-0000-0000-0000-000000004302', 64002, 2027, 'Race Active B', 'FEMALE', 'CHESTNUT', 'Race Sire B', 'Race Line B', 'Race Dam B', '00000000-0000-0000-0000-000000004102', 'ACTIVE'),
  ('00000000-0000-0000-0000-000000004303', 64003, 2027, 'Race Training A', 'MALE', 'BROWN', 'Race Sire C', 'Race Line C', 'Race Dam C', '00000000-0000-0000-0000-000000004101', 'TRAINING'),
  ('00000000-0000-0000-0000-000000004304', 64004, 2027, 'Race Injured A', 'FEMALE', 'GREY', 'Race Sire D', 'Race Line D', 'Race Dam D', '00000000-0000-0000-0000-000000004101', 'ACTIVE'),
  ('00000000-0000-0000-0000-000000004305', 64005, 2027, 'Race Changes Stage', 'MALE', 'BAY', 'Race Sire E', 'Race Line E', 'Race Dam E', '00000000-0000-0000-0000-000000004101', 'ACTIVE'),
  ('00000000-0000-0000-0000-000000004306', 64006, 2027, 'Race Direct GM', 'FEMALE', 'BAY', 'Race Sire F', 'Race Line F', 'Race Dam F', '00000000-0000-0000-0000-000000004101', 'ACTIVE'),
  ('00000000-0000-0000-0000-000000004307', 64007, 2027, 'Race Direct No Owner', 'MALE', 'BROWN', 'Race Sire G', 'Race Line G', 'Race Dam G', null, 'ACTIVE'),
  ('00000000-0000-0000-0000-000000004308', 64008, 2027, 'Race Direct Injured', 'FEMALE', 'GREY', 'Race Sire H', 'Race Line H', 'Race Dam H', '00000000-0000-0000-0000-000000004101', 'ACTIVE');

insert into public.injuries (
  horse_id, status,
  wp_start_year, wp_start_month, wp_start_week,
  wp_end_year, wp_end_month, wp_end_week
)
values (
  '00000000-0000-0000-0000-000000004304', 'ACTIVE',
  2030, 4, 2,
  2030, 4, 3
), (
  '00000000-0000-0000-0000-000000004308', 'ACTIVE',
  2030, 5, 2,
  2030, 5, 3
);

insert into public.race_catalog (id, name, grade, default_wp_month, default_wp_week, is_active)
values
  ('00000000-0000-0000-0000-000000004401', 'Default Week Two G2', 'G2', 4, 2, true),
  ('00000000-0000-0000-0000-000000004402', 'Alternate Week Two OP', 'OP', 4, 2, true),
  ('00000000-0000-0000-0000-000000004403', 'Inactive Race', 'OP', 5, 1, false);

-- PLAYER A can create multiple same-week PENDING requests for the same
-- ACTIVE Horse. They remain private intent, not schedule conflicts.
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000004201', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select public.submit_race_entry_request(
  '00000000-0000-0000-0000-000000004301', 2030, 4::smallint, 2::smallint,
  'CATALOG'::public.race_entry_race_kind, '00000000-0000-0000-0000-000000004401', null, null, null, 'first planned race'
);
select set_config('test.race.primary_request_id', (
  select id::text from public.race_entry_requests
  where horse_id = '00000000-0000-0000-0000-000000004301'
    and player_note = 'first planned race'
), true);

select public.submit_race_entry_request(
  '00000000-0000-0000-0000-000000004301', 2030, 4::smallint, 2::smallint,
  'CATALOG'::public.race_entry_race_kind, '00000000-0000-0000-0000-000000004401', null, null, null, 'conflicting pending is allowed'
);
select set_config('test.race.conflict_request_id', (
  select id::text from public.race_entry_requests
  where horse_id = '00000000-0000-0000-0000-000000004301'
    and player_note = 'conflicting pending is allowed'
), true);

do $$
begin
  begin
    perform public.submit_race_entry_request(
      '00000000-0000-0000-0000-000000004302', 2030, 4::smallint, 2::smallint,
      'CATALOG'::public.race_entry_race_kind, '00000000-0000-0000-0000-000000004401', null, null, null, null
    );
    raise exception 'PLAYER A submitted a request for PLAYER B Horse' using errcode = 'XX000';
  exception when insufficient_privilege then null;
  end;

  begin
    perform public.submit_race_entry_request(
      '00000000-0000-0000-0000-000000004303', 2030, 4::smallint, 2::smallint,
      'CATALOG'::public.race_entry_race_kind, '00000000-0000-0000-0000-000000004401', null, null, null, null
    );
    raise exception 'PLAYER submitted a non-ACTIVE Horse' using errcode = 'XX000';
  exception when check_violation then null;
  end;

  begin
    perform public.submit_race_entry_request(
      '00000000-0000-0000-0000-000000004301', 2030, 3::smallint, 5::smallint,
      'CATALOG'::public.race_entry_race_kind, '00000000-0000-0000-0000-000000004401', null, null, null, null
    );
    raise exception 'PLAYER submitted a race-entry request in a past WP week' using errcode = 'XX000';
  exception when check_violation then null;
  end;

  begin
    update public.race_entry_requests
    set status = 'CONFIRMED'::public.race_entry_request_status
    where id = current_setting('test.race.primary_request_id', true)::uuid;
    raise exception 'PLAYER directly updated Request status' using errcode = 'XX000';
  exception when insufficient_privilege then null;
  end;

  begin
    perform public.confirm_race_entry_request(
      current_setting('test.race.primary_request_id', true)::uuid,
      2030, 4::smallint, 3::smallint,
      'CATALOG'::public.race_entry_race_kind, '00000000-0000-0000-0000-000000004402', null, null, null, null
    );
    raise exception 'PLAYER confirmed a Request' using errcode = 'XX000';
  exception when insufficient_privilege then null;
  end;

  begin
    perform public.create_gm_confirmed_race_entry(
      '00000000-0000-0000-0000-000000004306', 2030, 5::smallint, 1::smallint,
      'CATALOG'::public.race_entry_race_kind, '00000000-0000-0000-0000-000000004401', null, null, null, null
    );
    raise exception 'PLAYER created a direct GM race schedule' using errcode = 'XX000';
  exception when insufficient_privilege then null;
  end;

  begin
    insert into public.race_catalog (name, grade, default_wp_month, default_wp_week)
    values ('PLAYER must not write catalog', 'OP', 4, 2);
    raise exception 'PLAYER wrote Race Catalog directly' using errcode = 'XX000';
  exception when insufficient_privilege then null;
  end;
end;
$$;
reset role;

-- A request cannot be marked CONFIRMED before its authoritative schedule is
-- present. This exercises the reverse integrity trigger rather than relying
-- only on the application RPC.
do $$
begin
  begin
    update public.race_entry_requests
    set status = 'CONFIRMED'::public.race_entry_request_status,
        reviewed_at = clock_timestamp()
    where id = current_setting('test.race.primary_request_id', true)::uuid;
    raise exception 'request became CONFIRMED without a confirmed race entry' using errcode = 'XX000';
  exception when check_violation then null;
  end;
end;
$$;

-- GM adjusts both race and week. The Catalog's Week 2 default remains merely
-- a reference: the final Week 3 entry is accepted with null jockey/style.
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000004203', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select public.confirm_race_entry_request(
  current_setting('test.race.primary_request_id', true)::uuid,
  2030, 4::smallint, 3::smallint,
  'CATALOG'::public.race_entry_race_kind, '00000000-0000-0000-0000-000000004402', null, null, null, null
);
reset role;

do $$
begin
  if not exists (
    select 1
    from public.race_entry_requests as request
    where request.id = current_setting('test.race.primary_request_id', true)::uuid
      and request.status = 'CONFIRMED'::public.race_entry_request_status
      and request.requested_wp_year = 2030
      and request.requested_wp_month = 4
      and request.requested_wp_week = 2
      and request.requested_race_catalog_id = '00000000-0000-0000-0000-000000004401'
  ) or not exists (
    select 1
    from public.confirmed_race_entries as entry
    where entry.request_id = current_setting('test.race.primary_request_id', true)::uuid
      and entry.wp_year = 2030
      and entry.wp_month = 4
      and entry.wp_week = 3
      and entry.race_catalog_id = '00000000-0000-0000-0000-000000004402'
      and entry.jockey is null
      and entry.running_style is null
  ) or not exists (
    select 1
    from public.audit_logs
    where action = 'RACE_ENTRY_CONFIRMED'
      and entity_id = current_setting('test.race.primary_request_id', true)
      and before_data ->> 'requested_wp_week' = '2'
      and after_data ->> 'confirmed_wp_week' = '3'
      and before_data ->> 'requested_race_catalog_id' = '00000000-0000-0000-0000-000000004401'
      and after_data ->> 'confirmed_race_catalog_id' = '00000000-0000-0000-0000-000000004402'
  ) then
    raise exception 'GM race/time adjustment did not preserve requested and final facts';
  end if;
end;
$$;

-- Once confirmed, the reverse trigger also forbids reclassifying the request
-- as REJECTED or WITHDRAWN while its schedule exists.
do $$
begin
  begin
    update public.race_entry_requests
    set status = 'REJECTED'::public.race_entry_request_status,
        rejection_reason = 'must not bypass confirmed schedule'
    where id = current_setting('test.race.primary_request_id', true)::uuid;
    raise exception 'confirmed Request became REJECTED with a schedule' using errcode = 'XX000';
  exception when check_violation then null;
  end;

  begin
    update public.race_entry_requests
    set status = 'WITHDRAWN'::public.race_entry_request_status,
        reviewed_by_user_id = null,
        reviewed_at = null,
        rejection_reason = null,
        withdrawn_at = clock_timestamp()
    where id = current_setting('test.race.primary_request_id', true)::uuid;
    raise exception 'confirmed Request became WITHDRAWN with a schedule' using errcode = 'XX000';
  exception when check_violation then null;
  end;
end;
$$;

-- Repeating an identical GM confirm is idempotent. A competing PENDING
-- Request for the same Horse/final week is atomically rejected by the unique
-- final-schedule constraint and stays PENDING.
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000004203', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select public.confirm_race_entry_request(
  current_setting('test.race.primary_request_id', true)::uuid,
  2030, 4::smallint, 3::smallint,
  'CATALOG'::public.race_entry_race_kind, '00000000-0000-0000-0000-000000004402', null, null, null, null
);
do $$
begin
  begin
    perform public.confirm_race_entry_request(
      current_setting('test.race.conflict_request_id', true)::uuid,
      2030, 3::smallint, 5::smallint,
      'CATALOG'::public.race_entry_race_kind, '00000000-0000-0000-0000-000000004402', null, null, null, null
    );
    raise exception 'GM confirmed a race-entry request in a past WP week' using errcode = 'XX000';
  exception when check_violation then null;
  end;

  begin
    perform public.confirm_race_entry_request(
      current_setting('test.race.conflict_request_id', true)::uuid,
      2030, 4::smallint, 3::smallint,
      'CATALOG'::public.race_entry_race_kind, '00000000-0000-0000-0000-000000004402', null, null, null, null
    );
    raise exception 'two confirmed entries occupied one Horse WP week' using errcode = 'XX000';
  exception when unique_violation then null;
  end;
end;
$$;
reset role;

do $$
begin
  if (select count(*) from public.confirmed_race_entries where horse_id = '00000000-0000-0000-0000-000000004301' and wp_year = 2030 and wp_month = 4 and wp_week = 3) <> 1
    or (select status from public.race_entry_requests where id = current_setting('test.race.conflict_request_id', true)::uuid) <> 'PENDING'::public.race_entry_request_status then
    raise exception 'same-week confirmation conflict was not atomic';
  end if;
end;
$$;

-- Different weeks may be confirmed, including the free-text MAIDEN/CONDITION
-- family. Jockey and running style are optional but explicit values persist.
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000004201', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select public.submit_race_entry_request(
  '00000000-0000-0000-0000-000000004301', 2030, 4::smallint, 4::smallint,
  'MAIDEN'::public.race_entry_race_kind, null, '3岁未胜利', null, null, 'second career plan'
);
select set_config('test.race.maiden_request_id', (
  select id::text from public.race_entry_requests where player_note = 'second career plan'
), true);
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000004203', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select public.confirm_race_entry_request(
  current_setting('test.race.maiden_request_id', true)::uuid,
  2030, 4::smallint, 4::smallint,
  'MAIDEN'::public.race_entry_race_kind, null, '3岁未胜利', '武丰', '先', 'jockey assigned by GM'
);
reset role;

do $$
begin
  if not exists (
    select 1
    from public.confirmed_race_entries
    where request_id = current_setting('test.race.maiden_request_id', true)::uuid
      and race_kind = 'MAIDEN'::public.race_entry_race_kind
      and race_catalog_id is null
      and race_label = '3岁未胜利'
      and jockey = '武丰'
      and running_style = '先'
  ) then
    raise exception 'free-text race or optional jockey/running-style confirmation failed';
  end if;
end;
$$;

-- An ACTIVE injury blocks its inclusive end week, but a GM adjustment to the
-- next week is valid. This proves confirmation checks final, not requested,
-- time.
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000004201', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select public.submit_race_entry_request(
  '00000000-0000-0000-0000-000000004304', 2030, 4::smallint, 2::smallint,
  'CATALOG'::public.race_entry_race_kind, '00000000-0000-0000-0000-000000004401', null, null, null, 'injury adjustment'
);
select set_config('test.race.injury_request_id', (
  select id::text from public.race_entry_requests where player_note = 'injury adjustment'
), true);
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000004203', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
do $$
begin
  begin
    perform public.confirm_race_entry_request(
      current_setting('test.race.injury_request_id', true)::uuid,
      2030, 4::smallint, 3::smallint,
      'CATALOG'::public.race_entry_race_kind, '00000000-0000-0000-0000-000000004401', null, null, null, null
    );
    raise exception 'injury-inclusive end week was confirmed' using errcode = 'XX000';
  exception when check_violation then null;
  end;
end;
$$;
select public.confirm_race_entry_request(
  current_setting('test.race.injury_request_id', true)::uuid,
  2030, 4::smallint, 4::smallint,
  'CATALOG'::public.race_entry_race_kind, '00000000-0000-0000-0000-000000004401', null, null, null, null
);
reset role;

-- A Horse that changes out of ACTIVE after submission cannot be confirmed.
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000004201', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select public.submit_race_entry_request(
  '00000000-0000-0000-0000-000000004305', 2030, 4::smallint, 5::smallint,
  'CATALOG'::public.race_entry_race_kind, '00000000-0000-0000-0000-000000004401', null, null, null, 'stage changes before review'
);
select set_config('test.race.stage_request_id', (
  select id::text from public.race_entry_requests where player_note = 'stage changes before review'
), true);
reset role;

update public.horses
set life_stage = 'TRAINING'::public.horse_life_stage
where id = '00000000-0000-0000-0000-000000004305';

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000004203', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
do $$
begin
  begin
    perform public.confirm_race_entry_request(
      current_setting('test.race.stage_request_id', true)::uuid,
      2030, 4::smallint, 5::smallint,
      'CATALOG'::public.race_entry_race_kind, '00000000-0000-0000-0000-000000004401', null, null, null, null
    );
    raise exception 'non-ACTIVE Horse was confirmed after submission' using errcode = 'XX000';
  exception when check_violation then null;
  end;
end;
$$;
reset role;

-- A GM may create an authoritative schedule with no fake PLAYER request. The
-- Owner comes from the locked Horse and request_id stays NULL. The same GM
-- path reuses final-time, race-identity, lifecycle, ownership, and injury
-- validation from request confirmation.
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000004203', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select public.create_gm_confirmed_race_entry(
  '00000000-0000-0000-0000-000000004306', 2030, 5::smallint, 1::smallint,
  'CATALOG'::public.race_entry_race_kind, '00000000-0000-0000-0000-000000004401', null,
  '横山武史', '差', 'GM authoritative direct schedule'
);
select set_config('test.race.direct_entry_id', (
  select id::text
  from public.confirmed_race_entries
  where horse_id = '00000000-0000-0000-0000-000000004306'
    and wp_year = 2030 and wp_month = 5 and wp_week = 1
), true);
-- An immediate exact retry returns the original direct entry, not a second row.
select set_config('test.race.direct_immediate_retry_entry_id', (
  select (public.create_gm_confirmed_race_entry(
    '00000000-0000-0000-0000-000000004306', 2030, 5::smallint, 1::smallint,
    'CATALOG'::public.race_entry_race_kind, '00000000-0000-0000-0000-000000004401', null,
    '横山武史', '差', 'GM authoritative direct schedule'
  )).id::text
), true);

do $$
begin
  begin
    perform public.create_gm_confirmed_race_entry(
      '00000000-0000-0000-0000-000000004307', 2030, 5::smallint, 1::smallint,
      'CATALOG'::public.race_entry_race_kind, '00000000-0000-0000-0000-000000004401', null, null, null, null
    );
    raise exception 'GM directly scheduled an ownerless Horse' using errcode = 'XX000';
  exception when check_violation then null;
  end;

  begin
    perform public.create_gm_confirmed_race_entry(
      '00000000-0000-0000-0000-000000004303', 2030, 5::smallint, 1::smallint,
      'CATALOG'::public.race_entry_race_kind, '00000000-0000-0000-0000-000000004401', null, null, null, null
    );
    raise exception 'GM directly scheduled a non-ACTIVE Horse' using errcode = 'XX000';
  exception when check_violation then null;
  end;

  begin
    perform public.create_gm_confirmed_race_entry(
      '00000000-0000-0000-0000-000000004306', 2030, 3::smallint, 5::smallint,
      'CATALOG'::public.race_entry_race_kind, '00000000-0000-0000-0000-000000004401', null, null, null, null
    );
    raise exception 'GM directly scheduled a race in a past WP week' using errcode = 'XX000';
  exception when check_violation then null;
  end;

  begin
    perform public.create_gm_confirmed_race_entry(
      '00000000-0000-0000-0000-000000004306', 2030, 5::smallint, 2::smallint,
      'CATALOG'::public.race_entry_race_kind, '00000000-0000-0000-0000-000000004403', null, null, null, null
    );
    raise exception 'GM directly scheduled an inactive catalog race' using errcode = 'XX000';
  exception when check_violation then null;
  end;

  begin
    perform public.create_gm_confirmed_race_entry(
      '00000000-0000-0000-0000-000000004306', 2030, 5::smallint, 2::smallint,
      'OTHER'::public.race_entry_race_kind, null, null, null, null, null
    );
    raise exception 'GM direct schedule accepted no race identity' using errcode = 'XX000';
  exception when check_violation then null;
  end;

  begin
    perform public.create_gm_confirmed_race_entry(
      '00000000-0000-0000-0000-000000004308', 2030, 5::smallint, 3::smallint,
      'CATALOG'::public.race_entry_race_kind, '00000000-0000-0000-0000-000000004401', null, null, null, null
    );
    raise exception 'GM direct schedule ignored an injury end week' using errcode = 'XX000';
  exception when check_violation then null;
  end;
end;
$$;
select public.create_gm_confirmed_race_entry(
  '00000000-0000-0000-0000-000000004308', 2030, 5::smallint, 4::smallint,
  'CATALOG'::public.race_entry_race_kind, '00000000-0000-0000-0000-000000004401', null, null, null, null
);
reset role;

do $$
begin
  if not exists (
    select 1
    from public.confirmed_race_entries
    where horse_id = '00000000-0000-0000-0000-000000004306'
      and owner_id = '00000000-0000-0000-0000-000000004101'
      and request_id is null
      and jockey = '横山武史'
      and running_style = '差'
  ) or (select count(*) from public.confirmed_race_entries where horse_id = '00000000-0000-0000-0000-000000004306' and wp_year = 2030 and wp_month = 5 and wp_week = 1) <> 1
    or current_setting('test.race.direct_entry_id', true) <> current_setting('test.race.direct_immediate_retry_entry_id', true)
    or not exists (
      select 1 from public.audit_logs
      where action = 'RACE_ENTRY_DIRECTLY_CONFIRMED'
        and after_data ->> 'horse_id' = '00000000-0000-0000-0000-000000004306'
    ) then
    raise exception 'GM direct confirmed race entry did not preserve authoritative facts';
  end if;
end;
$$;

-- Withdraw and reject are history-preserving state changes. Neither can later
-- be confirmed, and a confirmed schedule cannot be withdrawn by its PLAYER.
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000004201', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select public.submit_race_entry_request(
  '00000000-0000-0000-0000-000000004301', 2030, 5::smallint, 1::smallint,
  'CONDITION'::public.race_entry_race_kind, null, '1胜Class', null, null, 'withdraw me'
);
select set_config('test.race.withdraw_request_id', (
  select id::text from public.race_entry_requests where player_note = 'withdraw me'
), true);
select public.withdraw_race_entry_request(current_setting('test.race.withdraw_request_id', true)::uuid);

do $$
begin
  begin
    perform public.withdraw_race_entry_request(current_setting('test.race.primary_request_id', true)::uuid);
    raise exception 'PLAYER withdrew an already confirmed schedule' using errcode = 'XX000';
  exception when check_violation then null;
  end;
end;
$$;
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000004201', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select public.submit_race_entry_request(
  '00000000-0000-0000-0000-000000004301', 2030, 5::smallint, 2::smallint,
  'OTHER'::public.race_entry_race_kind, null, '地方交流赛', null, null, 'reject me'
);
select set_config('test.race.reject_request_id', (
  select id::text from public.race_entry_requests where player_note = 'reject me'
), true);
select public.submit_race_entry_request(
  '00000000-0000-0000-0000-000000004301', 2030, 5::smallint, 3::smallint,
  'CATALOG'::public.race_entry_race_kind, '00000000-0000-0000-0000-000000004401', null, null, null, 'invalid final identity'
);
select set_config('test.race.invalid_final_request_id', (
  select id::text from public.race_entry_requests where player_note = 'invalid final identity'
), true);
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000004203', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select public.reject_race_entry_request(current_setting('test.race.reject_request_id', true)::uuid, 'WP schedule changed');
do $$
begin
  begin
    perform public.confirm_race_entry_request(
      current_setting('test.race.withdraw_request_id', true)::uuid,
      2030, 5::smallint, 1::smallint,
      'CONDITION'::public.race_entry_race_kind, null, '1胜Class', null, null, null
    );
    raise exception 'WITHDRAWN Request was confirmed' using errcode = 'XX000';
  exception when check_violation then null;
  end;

  begin
    perform public.confirm_race_entry_request(
      current_setting('test.race.reject_request_id', true)::uuid,
      2030, 5::smallint, 2::smallint,
      'OTHER'::public.race_entry_race_kind, null, '地方交流赛', null, null, null
    );
    raise exception 'REJECTED Request was confirmed' using errcode = 'XX000';
  exception when check_violation then null;
  end;

  begin
    perform public.confirm_race_entry_request(
      current_setting('test.race.invalid_final_request_id', true)::uuid,
      2030, 5::smallint, 3::smallint,
      'OTHER'::public.race_entry_race_kind, null, null, null, null, null
    );
    raise exception 'confirmed entry accepted no race identity' using errcode = 'XX000';
  exception when check_violation then null;
  end;
end;
$$;
reset role;

-- Request privacy and confirmed-schedule visibility use real authenticated
-- contexts. PLAYER B can see the safe public projection of A's confirmed
-- schedule, but cannot read the GM-only base table or A's private intent.
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000004202', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select public.submit_race_entry_request(
  '00000000-0000-0000-0000-000000004302', 2030, 4::smallint, 1::smallint,
  'CATALOG'::public.race_entry_race_kind, '00000000-0000-0000-0000-000000004401', null, null, null, 'current week is allowed'
);
do $$
begin
  if not exists (select 1 from public.race_catalog where id = '00000000-0000-0000-0000-000000004401')
    or exists (select 1 from public.confirmed_race_entries)
    or not exists (
      select 1
      from public.confirmed_race_entries_public
      where horse_id = '00000000-0000-0000-0000-000000004301'
        and wp_year = 2030 and wp_month = 4 and wp_week = 3
    )
    or not exists (select 1 from public.race_entry_requests where owner_id = '00000000-0000-0000-0000-000000004102' and player_note = 'current week is allowed')
    or exists (select 1 from public.race_entry_requests where owner_id = '00000000-0000-0000-0000-000000004101') then
    raise exception 'PLAYER Race Management RLS visibility is incorrect';
  end if;
end;
$$;
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000004203', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
do $$
begin
  if (select count(*) from public.race_entry_requests) < 7
    or not exists (
      select 1 from public.confirmed_race_entries
      where horse_id = '00000000-0000-0000-0000-000000004306'
        and request_id is null
    ) then
    raise exception 'GM could not read all Race Management records';
  end if;
end;
$$;
reset role;

-- A successful direct entry remains idempotent after later game-world changes.
-- Its retry checks the existing entry under the Horse lock before applying
-- validation that is only relevant to a new schedule.
update public.game_state
set current_wp_year = 2030,
    current_wp_month = 5,
    current_wp_week = 2
where id;

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000004203', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('test.race.direct_past_retry_entry_id', (
  select (public.create_gm_confirmed_race_entry(
    '00000000-0000-0000-0000-000000004306', 2030, 5::smallint, 1::smallint,
    'CATALOG'::public.race_entry_race_kind, '00000000-0000-0000-0000-000000004401', null,
    '横山武史', '差', 'GM authoritative direct schedule'
  )).id::text
), true);
reset role;

update public.horses
set life_stage = 'TRAINING'::public.horse_life_stage
where id = '00000000-0000-0000-0000-000000004306';

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000004203', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('test.race.direct_inactive_horse_retry_entry_id', (
  select (public.create_gm_confirmed_race_entry(
    '00000000-0000-0000-0000-000000004306', 2030, 5::smallint, 1::smallint,
    'CATALOG'::public.race_entry_race_kind, '00000000-0000-0000-0000-000000004401', null,
    '横山武史', '差', 'GM authoritative direct schedule'
  )).id::text
), true);
do $$
begin
  begin
    perform public.create_gm_confirmed_race_entry(
      '00000000-0000-0000-0000-000000004306', 2030, 5::smallint, 4::smallint,
      'CATALOG'::public.race_entry_race_kind, '00000000-0000-0000-0000-000000004401', null, null, null, null
    );
    raise exception 'non-ACTIVE Horse received a new direct schedule' using errcode = 'XX000';
  exception when check_violation then null;
  end;
end;
$$;
reset role;

update public.race_catalog
set is_active = false
where id = '00000000-0000-0000-0000-000000004401';

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000004203', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('test.race.direct_inactive_catalog_retry_entry_id', (
  select (public.create_gm_confirmed_race_entry(
    '00000000-0000-0000-0000-000000004308', 2030, 5::smallint, 4::smallint,
    'CATALOG'::public.race_entry_race_kind, '00000000-0000-0000-0000-000000004401', null, null, null, null
  )).id::text
), true);
do $$
begin
  begin
    perform public.create_gm_confirmed_race_entry(
      '00000000-0000-0000-0000-000000004308', 2030, 5::smallint, 5::smallint,
      'CATALOG'::public.race_entry_race_kind, '00000000-0000-0000-0000-000000004401', null, null, null, null
    );
    raise exception 'inactive catalog received a new direct schedule' using errcode = 'XX000';
  exception when check_violation then null;
  end;

  begin
    perform public.create_gm_confirmed_race_entry(
      '00000000-0000-0000-0000-000000004308', 2030, 5::smallint, 4::smallint,
      'OTHER'::public.race_entry_race_kind, null, 'different race facts', null, null, null
    );
    raise exception 'different direct facts reused an existing direct schedule' using errcode = 'XX000';
  exception when unique_violation then null;
  end;

  begin
    perform public.create_gm_confirmed_race_entry(
      '00000000-0000-0000-0000-000000004301', 2030, 4::smallint, 3::smallint,
      'CATALOG'::public.race_entry_race_kind, '00000000-0000-0000-0000-000000004402', null, null, null, null
    );
    raise exception 'direct retry reused a request-backed confirmed schedule' using errcode = 'XX000';
  exception when unique_violation then null;
  end;
end;
$$;
reset role;

do $$
begin
  if current_setting('test.race.direct_entry_id', true) <> current_setting('test.race.direct_past_retry_entry_id', true)
    or current_setting('test.race.direct_entry_id', true) <> current_setting('test.race.direct_inactive_horse_retry_entry_id', true)
    or (select id::text from public.confirmed_race_entries where horse_id = '00000000-0000-0000-0000-000000004308' and wp_year = 2030 and wp_month = 5 and wp_week = 4) <> current_setting('test.race.direct_inactive_catalog_retry_entry_id', true)
    or (select count(*) from public.confirmed_race_entries where horse_id = '00000000-0000-0000-0000-000000004306' and wp_year = 2030 and wp_month = 5 and wp_week = 1) <> 1
    or (select count(*) from public.confirmed_race_entries where horse_id = '00000000-0000-0000-0000-000000004308' and wp_year = 2030 and wp_month = 5 and wp_week = 4) <> 1 then
    raise exception 'direct retry after game-world state changes was not idempotent';
  end if;
end;
$$;

do $$
begin
  if not exists (select 1 from public.audit_logs where action = 'RACE_ENTRY_REQUEST_CREATED')
    or not exists (select 1 from public.audit_logs where action = 'RACE_ENTRY_REQUEST_WITHDRAWN')
    or not exists (select 1 from public.audit_logs where action = 'RACE_ENTRY_CONFIRMED')
    or not exists (select 1 from public.audit_logs where action = 'RACE_ENTRY_DIRECTLY_CONFIRMED')
    or not exists (select 1 from public.audit_logs where action = 'RACE_ENTRY_REJECTED') then
    raise exception 'Race Management lifecycle audit coverage is incomplete';
  end if;
end;
$$;

-- Auth-user removal must preserve resolved Request and confirmed schedule
-- history, nulling only optional actor references.
delete from auth.users
where id = '00000000-0000-0000-0000-000000004203';

do $$
begin
  if (select status from public.race_entry_requests where id = current_setting('test.race.primary_request_id', true)::uuid) <> 'CONFIRMED'::public.race_entry_request_status
    or (select reviewed_at is not null and reviewed_by_user_id is null from public.race_entry_requests where id = current_setting('test.race.primary_request_id', true)::uuid) is not true
    or (select confirmed_by_user_id is null from public.confirmed_race_entries where request_id = current_setting('test.race.primary_request_id', true)::uuid) is not true
    or (select confirmed_by_user_id is null from public.confirmed_race_entries where horse_id = '00000000-0000-0000-0000-000000004306' and request_id is null) is not true
    or not exists (select 1 from public.audit_logs where action = 'RACE_ENTRY_CONFIRMED' and entity_id = current_setting('test.race.primary_request_id', true) and actor_user_id is null)
    or not exists (select 1 from public.audit_logs where action = 'RACE_ENTRY_DIRECTLY_CONFIRMED' and actor_user_id is null) then
    raise exception 'Auth deletion broke Race Management historical records';
  end if;
end;
$$;

rollback;
