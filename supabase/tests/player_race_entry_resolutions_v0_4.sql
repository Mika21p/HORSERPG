-- Local-only verification for 20260819090000_add_player_race_entry_resolution_rpc.sql.
-- Run after `npx supabase db reset`; all fixtures are rolled back and this
-- file must never be run against a remote or production database.

begin;

do $$
declare
  v_function regprocedure := 'public.get_current_player_race_entry_resolutions()'::regprocedure;
begin
  if not exists (
    select 1
    from pg_proc as procedure
    where procedure.oid = v_function
      and procedure.prosecdef
      and 'search_path=""' = any(coalesce(procedure.proconfig, array[]::text[]))
  ) then
    raise exception 'race-entry resolution RPC lacks SECURITY DEFINER or fixed search_path';
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
    raise exception 'race-entry resolution RPC execute ACL is incorrect';
  end if;
end;
$$;

set local role anon;
do $$
begin
  begin
    perform public.get_current_player_race_entry_resolutions();
    raise exception 'anon invoked the PLAYER race-entry resolution RPC' using errcode = 'XX000';
  exception when insufficient_privilege then null;
  end;
end;
$$;
reset role;

set local role service_role;
do $$
begin
  begin
    perform public.get_current_player_race_entry_resolutions();
    raise exception 'service_role invoked the PLAYER race-entry resolution RPC' using errcode = 'XX000';
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
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000005201', 'authenticated', 'authenticated', 'race-resolution-player-a@example.test', 'not-used', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000005202', 'authenticated', 'authenticated', 'race-resolution-player-b@example.test', 'not-used', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000005203', 'authenticated', 'authenticated', 'race-resolution-gm@example.test', 'not-used', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000005204', 'authenticated', 'authenticated', 'race-resolution-unbound@example.test', 'not-used', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now());

insert into public.owners (id, display_name, initial_funds)
values
  ('00000000-0000-0000-0000-000000005101', 'Race Resolution Owner A', 100000000),
  ('00000000-0000-0000-0000-000000005102', 'Race Resolution Owner B', 100000000);

insert into public.user_profiles (id, role, owner_id, display_name)
values
  ('00000000-0000-0000-0000-000000005201', 'PLAYER', '00000000-0000-0000-0000-000000005101', 'Race Resolution Player A'),
  ('00000000-0000-0000-0000-000000005202', 'PLAYER', '00000000-0000-0000-0000-000000005102', 'Race Resolution Player B'),
  ('00000000-0000-0000-0000-000000005203', 'GM', null, 'Race Resolution GM');

insert into public.game_state (id, current_wp_year, current_wp_month, current_wp_week, updated_by_user_id)
values (true, 2033, 4, 1, '00000000-0000-0000-0000-000000005203');

insert into public.horses (
  id, horse_number, birth_year, foal_name, sex, coat_color,
  sire_name, sire_line, broodmare_sire_name, owner_id, life_stage
)
values
  ('00000000-0000-0000-0000-000000005301', 65001, 2030, 'Race Resolution Horse A', 'MALE', 'BAY', 'Resolution Sire A', 'Resolution Line A', 'Resolution Dam A', '00000000-0000-0000-0000-000000005101', 'ACTIVE'),
  ('00000000-0000-0000-0000-000000005302', 65002, 2030, 'Race Resolution Horse B', 'FEMALE', 'CHESTNUT', 'Resolution Sire B', 'Resolution Line B', 'Resolution Dam B', '00000000-0000-0000-0000-000000005102', 'ACTIVE');

insert into public.race_catalog (id, name, grade, default_wp_month, default_wp_week, is_active)
values
  ('00000000-0000-0000-0000-000000005401', 'Resolution Requested Race', 'G3', 4, 2, true),
  ('00000000-0000-0000-0000-000000005402', 'Resolution Final Race', 'G2', 4, 3, true);

-- PLAYER A creates one eventual confirmed request and three non-confirmed
-- requests. Only the resolved request may later appear in the safe RPC.
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000005201', true);
select set_config('request.jwt.claim.role', 'authenticated', true);

select set_config('test.race_resolution.a_confirmed_request_id', (
  select (public.submit_race_entry_request(
    '00000000-0000-0000-0000-000000005301', 2033, 4::smallint, 2::smallint,
    'CATALOG'::public.race_entry_race_kind, '00000000-0000-0000-0000-000000005401', null,
    'Requested Jockey A', '先行', 'resolution confirmed request'
  )).id::text
), true);

select set_config('test.race_resolution.a_pending_request_id', (
  select (public.submit_race_entry_request(
    '00000000-0000-0000-0000-000000005301', 2033, 4::smallint, 4::smallint,
    'OTHER'::public.race_entry_race_kind, null, 'Pending Race', null, null, 'resolution pending request'
  )).id::text
), true);

select set_config('test.race_resolution.a_withdrawn_request_id', (
  select (public.submit_race_entry_request(
    '00000000-0000-0000-0000-000000005301', 2033, 4::smallint, 5::smallint,
    'CONDITION'::public.race_entry_race_kind, null, 'Withdrawn Race', null, null, 'resolution withdrawn request'
  )).id::text
), true);
select public.withdraw_race_entry_request(current_setting('test.race_resolution.a_withdrawn_request_id', true)::uuid);

select set_config('test.race_resolution.a_rejected_request_id', (
  select (public.submit_race_entry_request(
    '00000000-0000-0000-0000-000000005301', 2033, 5::smallint, 1::smallint,
    'MAIDEN'::public.race_entry_race_kind, null, 'Rejected Race', null, null, 'resolution rejected request'
  )).id::text
), true);
reset role;

-- PLAYER B creates a separate request that becomes a different confirmed
-- entry. It must never be visible in A's private resolution mapping.
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000005202', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('test.race_resolution.b_confirmed_request_id', (
  select (public.submit_race_entry_request(
    '00000000-0000-0000-0000-000000005302', 2033, 4::smallint, 2::smallint,
    'CATALOG'::public.race_entry_race_kind, '00000000-0000-0000-0000-000000005401', null,
    null, null, 'resolution B confirmed request'
  )).id::text
), true);
reset role;

-- GM changes A's requested race and requested time when confirming it, rejects
-- A's separate request, confirms B's request, and creates a GM-direct entry
-- for A's Horse. The mapping must represent only request-backed entries.
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000005203', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('test.race_resolution.a_confirmed_entry_id', (
  select (public.confirm_race_entry_request(
    current_setting('test.race_resolution.a_confirmed_request_id', true)::uuid,
    2033, 4::smallint, 3::smallint,
    'CATALOG'::public.race_entry_race_kind, '00000000-0000-0000-0000-000000005402', null,
    'Final Jockey A', '差', 'private GM adjustment note'
  )).id::text
), true);
select public.reject_race_entry_request(
  current_setting('test.race_resolution.a_rejected_request_id', true)::uuid,
  'GM rejected this separate request'
);
select set_config('test.race_resolution.b_confirmed_entry_id', (
  select (public.confirm_race_entry_request(
    current_setting('test.race_resolution.b_confirmed_request_id', true)::uuid,
    2033, 4::smallint, 3::smallint,
    'CATALOG'::public.race_entry_race_kind, '00000000-0000-0000-0000-000000005402', null,
    'Final Jockey B', '逃', 'private GM note B'
  )).id::text
), true);
select set_config('test.race_resolution.direct_entry_id', (
  select (public.create_gm_confirmed_race_entry(
    '00000000-0000-0000-0000-000000005301', 2033, 4::smallint, 5::smallint,
    'OTHER'::public.race_entry_race_kind, null, 'GM Direct Race', 'GM Direct Jockey', '追込', 'private GM direct note'
  )).id::text
), true);
reset role;

-- PLAYER A receives precisely its confirmed request mapping, including the
-- adjusted final facts. Neither other request states, B's mapping, GM-direct
-- entry, nor internal fields appear in the RPC result or JSON payload.
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000005201', true);
select set_config('request.jwt.claim.role', 'authenticated', true);

do $$
declare
  v_request_id uuid;
  v_entry_id uuid;
  v_year integer;
  v_month smallint;
  v_week smallint;
  v_catalog_id uuid;
  v_jockey text;
  v_style text;
  v_payload jsonb;
begin
  if (select count(*) from public.get_current_player_race_entry_resolutions()) <> 1 then
    raise exception 'PLAYER A received a non-confirmed, foreign, or GM-direct race resolution';
  end if;

  select
    resolution.request_id,
    resolution.confirmed_entry_id,
    resolution.wp_year,
    resolution.wp_month,
    resolution.wp_week,
    resolution.race_catalog_id,
    resolution.jockey,
    resolution.running_style,
    to_jsonb(resolution)
  into v_request_id, v_entry_id, v_year, v_month, v_week, v_catalog_id, v_jockey, v_style, v_payload
  from public.get_current_player_race_entry_resolutions() as resolution;

  if v_request_id <> current_setting('test.race_resolution.a_confirmed_request_id', true)::uuid
    or v_entry_id <> current_setting('test.race_resolution.a_confirmed_entry_id', true)::uuid
    or v_year <> 2033
    or v_month <> 4
    or v_week <> 3
    or v_catalog_id <> '00000000-0000-0000-0000-000000005402'
    or v_jockey <> 'Final Jockey A'
    or v_style <> '差' then
    raise exception 'PLAYER A resolution did not return the exact GM-adjusted final entry';
  end if;

  if exists (
    select 1
    from public.get_current_player_race_entry_resolutions() as resolution
    where resolution.request_id in (
      current_setting('test.race_resolution.a_pending_request_id', true)::uuid,
      current_setting('test.race_resolution.a_withdrawn_request_id', true)::uuid,
      current_setting('test.race_resolution.a_rejected_request_id', true)::uuid,
      current_setting('test.race_resolution.b_confirmed_request_id', true)::uuid
    )
    or resolution.confirmed_entry_id = current_setting('test.race_resolution.direct_entry_id', true)::uuid
  ) then
    raise exception 'PLAYER A resolution leaked a non-confirmed, foreign, or GM-direct entry';
  end if;

  if v_payload ?| array['gm_note', 'confirmed_by_user_id', 'reviewed_by_user_id', 'owner_id', 'request_owner_id'] then
    raise exception 'PLAYER A resolution JSON leaked an internal field: %', v_payload;
  end if;
end;
$$;

do $$
begin
  if not exists (
    select 1
    from public.confirmed_race_entries_public
    where id = current_setting('test.race_resolution.direct_entry_id', true)::uuid
  ) then
    raise exception 'GM-direct entry is not visible through the public schedule';
  end if;
end;
$$;
reset role;

-- PLAYER B receives only B's exact private mapping.
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000005202', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
do $$
begin
  if (select count(*) from public.get_current_player_race_entry_resolutions()) <> 1
    or not exists (
      select 1
      from public.get_current_player_race_entry_resolutions() as resolution
      where resolution.request_id = current_setting('test.race_resolution.b_confirmed_request_id', true)::uuid
        and resolution.confirmed_entry_id = current_setting('test.race_resolution.b_confirmed_entry_id', true)::uuid
    )
    or exists (
      select 1
      from public.get_current_player_race_entry_resolutions() as resolution
      where resolution.request_id = current_setting('test.race_resolution.a_confirmed_request_id', true)::uuid
    ) then
    raise exception 'PLAYER B race-entry resolution isolation is incorrect';
  end if;
end;
$$;
reset role;

-- GM and an authenticated account with no valid PLAYER/Owner binding have an
-- EXECUTE grant through the shared authenticated role but are rejected by the
-- function's own caller-derived identity check.
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000005203', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
do $$
begin
  begin
    perform public.get_current_player_race_entry_resolutions();
    raise exception 'GM invoked the PLAYER race-entry resolution RPC' using errcode = 'XX000';
  exception when insufficient_privilege then null;
  end;
end;
$$;
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000005204', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
do $$
begin
  begin
    perform public.get_current_player_race_entry_resolutions();
    raise exception 'unbound authenticated user invoked the PLAYER race-entry resolution RPC' using errcode = 'XX000';
  exception when insufficient_privilege then null;
  end;
end;
$$;
reset role;

rollback;
