-- Local SQL verification for HorseRPG v0.4-E Retirement + Prize Release.
-- Run after `npx supabase db reset`.  Every fixture and temporary test trigger
-- rolls back at the end, so this file never leaves local data behind.

begin;

do $$
declare
  v_function text;
begin
  if not exists (
    select 1 from pg_enum as enum_value
    join pg_type as type_row on type_row.oid = enum_value.enumtypid
    join pg_namespace as namespace_row on namespace_row.oid = type_row.typnamespace
    where namespace_row.nspname = 'public'
      and type_row.typname = 'prize_receivable_status'
      and enum_value.enumlabel = 'RELEASED'
  ) or not exists (
    select 1 from pg_tables where schemaname = 'public' and tablename = 'horse_retirement_requests'
  ) or not exists (
    select 1 from pg_tables where schemaname = 'public' and tablename = 'prize_receivable_ledger_entries'
  ) then
    raise exception 'v0.4-E enum or tables are missing';
  end if;

  if not (
    select relrowsecurity from pg_class where oid = 'public.horse_retirement_requests'::regclass
  ) or not (
    select relrowsecurity from pg_class where oid = 'public.prize_receivable_ledger_entries'::regclass
  ) then
    raise exception 'v0.4-E tables must enable RLS';
  end if;

  if not exists (
    select 1 from pg_indexes
    where schemaname = 'public'
      and indexname in (
        'horse_retirement_requests_one_pending_per_horse_idx',
        'horse_retirement_requests_one_confirmed_per_horse_idx',
        'prize_receivable_ledger_entries_one_release_idx',
        'financial_transactions_prize_ledger_source_once_idx'
      )
    group by schemaname
    having count(*) = 4
  ) then
    raise exception 'v0.4-E exactly-once indexes are missing';
  end if;

  foreach v_function in array array[
    'public.submit_horse_retirement_request(uuid,text)'::text,
    'public.withdraw_horse_retirement_request(uuid)'::text,
    'public.create_gm_retirement_request(uuid,public.horse_retirement_request_kind,text)'::text,
    'public.reject_horse_retirement_request(uuid,text)'::text,
    'public.confirm_horse_retirement(uuid)'::text
  ] loop
    if not exists (
      select 1 from pg_proc as procedure
      where procedure.oid = v_function::regprocedure
        and procedure.prosecdef
        and procedure.proconfig is not null
        and procedure.proconfig::text like '%search_path=%'
    ) or has_function_privilege('public', v_function::regprocedure, 'EXECUTE')
      or has_function_privilege('anon', v_function::regprocedure, 'EXECUTE')
      or has_function_privilege('service_role', v_function::regprocedure, 'EXECUTE')
      or not has_function_privilege('authenticated', v_function::regprocedure, 'EXECUTE') then
      raise exception 'Retirement RPC has an incorrect security definition or ACL: %', v_function;
    end if;
  end loop;

  foreach v_function in array array[
    'public.append_prize_receivable_ledger_entry(uuid,uuid,public.prize_receivable_ledger_entry_kind,bigint,uuid,text)'::text,
    'public.release_prize_receivable(uuid,uuid,uuid,text)'::text,
    'public.release_pending_prizes_for_horse(uuid,uuid,uuid)'::text,
    'public.enforce_prize_receivable_ledger_entry_integrity()'::text,
    'public.enforce_no_pending_prizes_for_retired_horse()'::text
  ] loop
    if has_function_privilege('public', v_function::regprocedure, 'EXECUTE')
      or has_function_privilege('anon', v_function::regprocedure, 'EXECUTE')
      or has_function_privilege('authenticated', v_function::regprocedure, 'EXECUTE')
      or has_function_privilege('service_role', v_function::regprocedure, 'EXECUTE') then
      raise exception 'Retirement/prize internal helper is client-callable: %', v_function;
    end if;
  end loop;

  if has_table_privilege('authenticated', 'public.horse_retirement_requests', 'INSERT')
    or has_table_privilege('authenticated', 'public.horse_retirement_requests', 'UPDATE')
    or has_table_privilege('authenticated', 'public.horse_retirement_requests', 'DELETE')
    or has_table_privilege('authenticated', 'public.prize_receivable_ledger_entries', 'INSERT')
    or has_table_privilege('authenticated', 'public.prize_receivable_ledger_entries', 'UPDATE')
    or has_table_privilege('authenticated', 'public.prize_receivable_ledger_entries', 'DELETE') then
    raise exception 'v0.4-E base tables expose an authenticated write privilege';
  end if;
end;
$$;

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
values
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-00000000e101', 'authenticated', 'authenticated', 'retirement-player-a@example.test', 'not-used', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-00000000e102', 'authenticated', 'authenticated', 'retirement-player-b@example.test', 'not-used', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-00000000e103', 'authenticated', 'authenticated', 'retirement-gm@example.test', 'not-used', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now());

insert into public.owners (id, display_name, initial_funds)
values
  ('00000000-0000-0000-0000-00000000e201', 'Retirement Owner A', 100000000),
  ('00000000-0000-0000-0000-00000000e202', 'Retirement Owner B', 100000000);

insert into public.user_profiles (id, role, owner_id, display_name)
values
  ('00000000-0000-0000-0000-00000000e101', 'PLAYER', '00000000-0000-0000-0000-00000000e201', 'Retirement Player A'),
  ('00000000-0000-0000-0000-00000000e102', 'PLAYER', '00000000-0000-0000-0000-00000000e202', 'Retirement Player B'),
  ('00000000-0000-0000-0000-00000000e103', 'GM', null, 'Retirement GM');

insert into public.game_state (id, current_wp_year, current_wp_month, current_wp_week, updated_by_user_id)
values (true, 2040, 12, 5, '00000000-0000-0000-0000-00000000e103');

insert into public.horses (
  id, horse_number, birth_year, foal_name, sex, coat_color,
  sire_name, sire_line, broodmare_sire_name, owner_id, life_stage
)
values
  ('00000000-0000-0000-0000-00000000e301', 94101, 2038, 'Retirement Age Two', 'MALE', 'BAY', 'Sire 1', 'Line 1', 'Dam 1', '00000000-0000-0000-0000-00000000e201', 'ACTIVE'),
  ('00000000-0000-0000-0000-00000000e302', 94102, 2037, 'Retirement Age Three', 'FEMALE', 'BAY', 'Sire 2', 'Line 2', 'Dam 2', '00000000-0000-0000-0000-00000000e201', 'ACTIVE'),
  ('00000000-0000-0000-0000-00000000e303', 94103, 2036, 'Retirement Release Horse', 'MALE', 'BAY', 'Sire 3', 'Line 3', 'Dam 3', '00000000-0000-0000-0000-00000000e201', 'ACTIVE'),
  ('00000000-0000-0000-0000-00000000e304', 94104, 2036, 'Retirement Future Schedule', 'FEMALE', 'BAY', 'Sire 4', 'Line 4', 'Dam 4', '00000000-0000-0000-0000-00000000e201', 'ACTIVE'),
  ('00000000-0000-0000-0000-00000000e305', 94105, 2035, 'Retirement G1 Horse', 'MALE', 'BAY', 'Sire 5', 'Line 5', 'Dam 5', '00000000-0000-0000-0000-00000000e201', 'ACTIVE'),
  ('00000000-0000-0000-0000-00000000e306', 94106, 2036, 'Retirement Pending Void', 'FEMALE', 'BAY', 'Sire 6', 'Line 6', 'Dam 6', '00000000-0000-0000-0000-00000000e201', 'ACTIVE'),
  ('00000000-0000-0000-0000-00000000e307', 94107, 2036, 'Retirement Atomic Horse', 'MALE', 'BAY', 'Sire 7', 'Line 7', 'Dam 7', '00000000-0000-0000-0000-00000000e201', 'ACTIVE'),
  ('00000000-0000-0000-0000-00000000e310', 94110, 2036, 'Retirement Privacy Horse', 'FEMALE', 'BAY', 'Sire 10', 'Line 10', 'Dam 10', '00000000-0000-0000-0000-00000000e201', 'ACTIVE');

insert into public.race_catalog (id, name, grade, default_wp_month, default_wp_week, is_active)
values
  ('00000000-0000-0000-0000-00000000e401', 'Retirement Test G2', 'G2', 12, 5, true),
  ('00000000-0000-0000-0000-00000000e402', 'Retirement Test G1', 'G1', 1, 1, true);

-- PLAYER owner eligibility, idempotent submit, withdrawal, GM rejection, and
-- real RLS isolation all run under authenticated JWT context.
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000e101', true);
select set_config('request.jwt.claim.role', 'authenticated', true);

do $$
begin
  begin
    perform public.submit_horse_retirement_request('00000000-0000-0000-0000-00000000e301', null);
    raise exception '2-year-old Owner retirement request should fail';
  exception when sqlstate '23514' then null;
  end;
end;
$$;

select set_config('test.retirement.owner_request_id', (
  select id::text from public.submit_horse_retirement_request(
    '00000000-0000-0000-0000-00000000e302', 'Owner retirement request'
  )
), true);

select public.submit_horse_retirement_request(
  '00000000-0000-0000-0000-00000000e302', 'Owner retirement request'
);

do $$
begin
  if (select count(*) from public.horse_retirement_requests
      where horse_id = '00000000-0000-0000-0000-00000000e302'
        and status = 'PENDING'::public.horse_retirement_request_status) <> 1
    or (select life_stage from public.horses where id = '00000000-0000-0000-0000-00000000e302')
      <> 'RETIRE_PENDING'::public.horse_life_stage then
    raise exception 'Owner retirement submit was not idempotent or did not set RETIRE_PENDING';
  end if;
end;
$$;

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000e102', true);
select set_config('request.jwt.claim.role', 'authenticated', true);

do $$
begin
  if exists (
    select 1 from public.horse_retirement_requests
    where id = current_setting('test.retirement.owner_request_id', true)::uuid
  ) then
    raise exception 'PLAYER B can read PLAYER A retirement request';
  end if;

  begin
    perform public.withdraw_horse_retirement_request(current_setting('test.retirement.owner_request_id', true)::uuid);
    raise exception 'PLAYER B withdrawal should fail';
  exception when sqlstate '42501' then null;
  end;

  -- A Horse with no PENDING request must produce exactly the same owner error
  -- as one that does have a private PENDING request below.
  begin
    perform public.submit_horse_retirement_request(
      '00000000-0000-0000-0000-00000000e310', 'privacy probe'
    );
    raise exception 'PLAYER B must not submit retirement for Owner A Horse without a pending request';
  exception when sqlstate '42501' then
    if sqlerrm <> 'a PLAYER may request retirement only for that PLAYER Owner''s Horse' then
      raise;
    end if;
  end;

  begin
    perform public.create_gm_retirement_request(
      '00000000-0000-0000-0000-00000000e302',
      'WP_LIFESPAN'::public.horse_retirement_request_kind,
      'not allowed'
    );
    raise exception 'PLAYER forced retirement should fail';
  exception when sqlstate '42501' then null;
  end;
end;
$$;

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000e101', true);
select set_config('request.jwt.claim.role', 'authenticated', true);

select set_config('test.retirement.privacy_request_id', (
  select id::text from public.submit_horse_retirement_request(
    '00000000-0000-0000-0000-00000000e310', 'privacy request'
  )
), true);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000e102', true);
select set_config('request.jwt.claim.role', 'authenticated', true);

do $$
begin
  begin
    perform public.submit_horse_retirement_request(
      '00000000-0000-0000-0000-00000000e310', 'privacy request'
    );
    raise exception 'PLAYER B must not submit retirement for Owner A Horse with a pending request';
  exception when sqlstate '42501' then
    if sqlerrm <> 'a PLAYER may request retirement only for that PLAYER Owner''s Horse' then
      raise;
    end if;
  end;
end;
$$;

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000e101', true);
select set_config('request.jwt.claim.role', 'authenticated', true);

do $$
declare
  v_retry public.horse_retirement_requests;
begin
  select * into v_retry from public.submit_horse_retirement_request(
    '00000000-0000-0000-0000-00000000e310', 'privacy request'
  );

  if v_retry.id <> current_setting('test.retirement.privacy_request_id', true)::uuid then
    raise exception 'PLAYER identical retirement submit retry did not return its original request';
  end if;
end;
$$;

select public.withdraw_horse_retirement_request(
  current_setting('test.retirement.privacy_request_id', true)::uuid
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000e103', true);
select set_config('request.jwt.claim.role', 'authenticated', true);

do $$
begin
  begin
    perform public.create_gm_confirmed_race_entry(
      '00000000-0000-0000-0000-00000000e302', 2040, 12::smallint, 5::smallint,
      'CATALOG'::public.race_entry_race_kind, '00000000-0000-0000-0000-00000000e401', null, null, null, null
    );
    raise exception 'RETIRE_PENDING Horse should not receive a confirmed race entry';
  exception when sqlstate '23514' then null;
  end;
end;
$$;

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000e101', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select public.withdraw_horse_retirement_request(current_setting('test.retirement.owner_request_id', true)::uuid);
select public.withdraw_horse_retirement_request(current_setting('test.retirement.owner_request_id', true)::uuid);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000e103', true);
select set_config('request.jwt.claim.role', 'authenticated', true);

do $$
begin
  begin
    perform public.create_gm_retirement_request(
      '00000000-0000-0000-0000-00000000e302',
      'WP_LIFESPAN'::public.horse_retirement_request_kind,
      ' '
    );
    raise exception 'WP_LIFESPAN without a reason should fail';
  exception when sqlstate '23514' then null;
  end;
end;
$$;

select set_config('test.retirement.forced_request_id', (
  select id::text from public.create_gm_retirement_request(
    '00000000-0000-0000-0000-00000000e302',
    'WP_LIFESPAN'::public.horse_retirement_request_kind,
    'WP reported the lifespan retirement threshold'
  )
), true);
select public.reject_horse_retirement_request(
  current_setting('test.retirement.forced_request_id', true)::uuid, 'GM rejects this test request'
);
select public.reject_horse_retirement_request(
  current_setting('test.retirement.forced_request_id', true)::uuid, 'GM rejects this test request'
);

do $$
begin
  if (select life_stage from public.horses where id = '00000000-0000-0000-0000-00000000e302')
      <> 'ACTIVE'::public.horse_life_stage then
    raise exception 'withdraw/reject did not restore Horse ACTIVE';
  end if;
end;
$$;

-- Normal Horse CRUD may create an ordinary Horse, but it cannot enter or
-- leave either retirement lifecycle state.  The following writes use a real
-- GM JWT/RLS context rather than bypassing the application role.
do $$
begin
  begin
    insert into public.horses (
      id, horse_number, birth_year, foal_name, sex, coat_color,
      sire_name, sire_line, broodmare_sire_name, owner_id, life_stage
    ) values (
      '00000000-0000-0000-0000-00000000e309', 94109, 2036,
      'Retirement Lifecycle Horse', 'MALE', 'BAY', 'Sire 9', 'Line 9', 'Dam 9',
      '00000000-0000-0000-0000-00000000e201', 'RETIRED'
    );
    raise exception 'GM direct RETIRED Horse insert should fail';
  exception when sqlstate '42501' then null;
  end;

  insert into public.horses (
    id, horse_number, birth_year, foal_name, sex, coat_color,
    sire_name, sire_line, broodmare_sire_name, owner_id, life_stage
  ) values (
    '00000000-0000-0000-0000-00000000e309', 94109, 2036,
    'Retirement Lifecycle Horse', 'MALE', 'BAY', 'Sire 9', 'Line 9', 'Dam 9',
    '00000000-0000-0000-0000-00000000e201', 'ACTIVE'
  );

  begin
    update public.horses
    set life_stage = 'RETIRED'::public.horse_life_stage
    where id = '00000000-0000-0000-0000-00000000e309';
    raise exception 'GM direct ACTIVE to RETIRED should fail';
  exception when sqlstate '42501' then null;
  end;

  begin
    update public.horses
    set life_stage = 'RETIRE_PENDING'::public.horse_life_stage
    where id = '00000000-0000-0000-0000-00000000e309';
    raise exception 'GM direct ACTIVE to RETIRE_PENDING should fail';
  exception when sqlstate '42501' then null;
  end;
end;
$$;

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000e101', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('test.retirement.lifecycle_request_id', (
  select id::text from public.submit_horse_retirement_request(
    '00000000-0000-0000-0000-00000000e309', 'controlled lifecycle request'
  )
), true);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000e103', true);
select set_config('request.jwt.claim.role', 'authenticated', true);

do $$
begin
  begin
    update public.horses
    set life_stage = 'DISCARDED'::public.horse_life_stage
    where id = '00000000-0000-0000-0000-00000000e309';
    raise exception 'GM direct RETIRE_PENDING to DISCARDED should fail';
  exception when sqlstate '42501' then null;
  end;
end;
$$;

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000e101', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select public.withdraw_horse_retirement_request(
  current_setting('test.retirement.lifecycle_request_id', true)::uuid
);
select set_config('test.retirement.lifecycle_confirm_request_id', (
  select id::text from public.submit_horse_retirement_request(
    '00000000-0000-0000-0000-00000000e309', 'controlled lifecycle confirmation request'
  )
), true);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000e103', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select public.confirm_horse_retirement(
  current_setting('test.retirement.lifecycle_confirm_request_id', true)::uuid
);

do $$
begin
  begin
    update public.horses
    set life_stage = 'ACTIVE'::public.horse_life_stage
    where id = '00000000-0000-0000-0000-00000000e309';
    raise exception 'GM direct RETIRED to ACTIVE should fail';
  exception when sqlstate '42501' then null;
  end;

  begin
    update public.horses
    set life_stage = 'BREEDING'::public.horse_life_stage
    where id = '00000000-0000-0000-0000-00000000e309';
    raise exception 'GM direct RETIRED to BREEDING should fail';
  exception when sqlstate '42501' then null;
  end;

  if (select life_stage from public.horses where id = '00000000-0000-0000-0000-00000000e309')
       <> 'RETIRED'::public.horse_life_stage then
    raise exception 'controlled retirement confirmation did not preserve RETIRED lifecycle state';
  end if;
end;
$$;

-- Create a future schedule before retirement request, then prove confirm has no
-- state, release, or ledger side effect while that schedule remains future.
select public.create_gm_confirmed_race_entry(
  '00000000-0000-0000-0000-00000000e304', 2041, 1::smallint, 1::smallint,
  'CATALOG'::public.race_entry_race_kind, '00000000-0000-0000-0000-00000000e401', null, null, null, null
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000e101', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('test.retirement.future_request_id', (
  select id::text from public.submit_horse_retirement_request('00000000-0000-0000-0000-00000000e304', null)
), true);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000e103', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
do $$
begin
  begin
    perform public.confirm_horse_retirement(current_setting('test.retirement.future_request_id', true)::uuid);
    raise exception 'future confirmed schedule should block retirement confirmation';
  exception when sqlstate '23514' then null;
  end;

  if (select life_stage from public.horses where id = '00000000-0000-0000-0000-00000000e304')
      <> 'RETIRE_PENDING'::public.horse_life_stage
    or exists (select 1 from public.prize_receivable_ledger_entries where retirement_request_id = current_setting('test.retirement.future_request_id', true)::uuid) then
    raise exception 'future schedule failure leaked retirement side effects';
  end if;
end;
$$;
select public.reject_horse_retirement_request(current_setting('test.retirement.future_request_id', true)::uuid, 'future schedule cleanup');

-- Construct three historically-owned PENDING prizes for one current Horse:
-- two belong to Owner A and one belongs to Owner B.  The second/third entries
-- are controlled GM fixture rows so the test can prove release does not pay the
-- current Horse owner by mistake.
select public.create_gm_confirmed_race_entry(
  '00000000-0000-0000-0000-00000000e303', 2040, 12::smallint, 5::smallint,
  'CATALOG'::public.race_entry_race_kind, '00000000-0000-0000-0000-00000000e401', null, null, null, null
);
select public.create_actual_race(2040, 12::smallint, 5::smallint, 'CATALOG'::public.race_entry_race_kind, '00000000-0000-0000-0000-00000000e401', null);
select public.record_race_result(
  (select id from public.confirmed_race_entries where horse_id = '00000000-0000-0000-0000-00000000e303' and wp_week = 5),
  (select id from public.actual_races where race_catalog_id = '00000000-0000-0000-0000-00000000e401' and wp_week = 5),
  1::smallint, 10000000::bigint, null, null, null
);

reset role;
select set_config('horserpg.gm_direct_race_entry', 'on', true);
insert into public.confirmed_race_entries (
  horse_id, owner_id, wp_year, wp_month, wp_week, race_kind, race_catalog_id,
  confirmed_by_user_id
) values
  ('00000000-0000-0000-0000-00000000e303', '00000000-0000-0000-0000-00000000e201', 2040, 12, 4, 'CATALOG', '00000000-0000-0000-0000-00000000e401', '00000000-0000-0000-0000-00000000e103'),
  ('00000000-0000-0000-0000-00000000e303', '00000000-0000-0000-0000-00000000e202', 2040, 12, 3, 'CATALOG', '00000000-0000-0000-0000-00000000e401', '00000000-0000-0000-0000-00000000e103');
insert into public.actual_races (
  wp_year, wp_month, wp_week, race_kind, race_catalog_id, race_name, grade, created_by_user_id
) values
  (2040, 12, 4, 'CATALOG', '00000000-0000-0000-0000-00000000e401', 'Retirement Test G2', 'G2', '00000000-0000-0000-0000-00000000e103'),
  (2040, 12, 3, 'CATALOG', '00000000-0000-0000-0000-00000000e401', 'Retirement Test G2', 'G2', '00000000-0000-0000-0000-00000000e103');
select public.record_race_result(
  (select id from public.confirmed_race_entries where horse_id = '00000000-0000-0000-0000-00000000e303' and wp_week = 4),
  (select id from public.actual_races where race_catalog_id = '00000000-0000-0000-0000-00000000e401' and wp_week = 4),
  2::smallint, 20000000::bigint, null, null, null
);
select public.record_race_result(
  (select id from public.confirmed_race_entries where horse_id = '00000000-0000-0000-0000-00000000e303' and wp_week = 3),
  (select id from public.actual_races where race_catalog_id = '00000000-0000-0000-0000-00000000e401' and wp_week = 3),
  3::smallint, 30000000::bigint, null, null, null
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000e101', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('test.retirement.release_request_id', (
  select id::text from public.submit_horse_retirement_request('00000000-0000-0000-0000-00000000e303', 'release all historical prizes')
), true);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000e103', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select public.confirm_horse_retirement(current_setting('test.retirement.release_request_id', true)::uuid);
select public.confirm_horse_retirement(current_setting('test.retirement.release_request_id', true)::uuid);

do $$
declare
  v_a_total bigint;
  v_b_total bigint;
  v_release_count integer;
  v_financial_count integer;
  v_audit_count integer;
begin
  select coalesce(sum(amount), 0) into v_a_total
  from public.financial_transactions
  where owner_id = '00000000-0000-0000-0000-00000000e201'
    and transaction_kind = 'PRIZE_RELEASE';
  select coalesce(sum(amount), 0) into v_b_total
  from public.financial_transactions
  where owner_id = '00000000-0000-0000-0000-00000000e202'
    and transaction_kind = 'PRIZE_RELEASE';
  select count(*) into v_release_count
  from public.prize_receivable_ledger_entries as ledger_entry
  join public.prize_receivables as receivable on receivable.id = ledger_entry.prize_receivable_id
  where receivable.horse_id = '00000000-0000-0000-0000-00000000e303'
    and ledger_entry.entry_kind = 'RELEASE';
  select count(*) into v_financial_count
  from public.financial_transactions
  where source_entity_type = 'PRIZE_RECEIVABLE_LEDGER_ENTRY';
  select count(*) into v_audit_count
  from public.audit_logs
  where action = 'HORSE_RETIREMENT_CONFIRMED'
    and entity_id = current_setting('test.retirement.release_request_id', true);

  if (select life_stage from public.horses where id = '00000000-0000-0000-0000-00000000e303')
       <> 'RETIRED'::public.horse_life_stage
    or (select count(*) from public.prize_receivables
        where horse_id = '00000000-0000-0000-0000-00000000e303'
          and status = 'RELEASED'::public.prize_receivable_status) <> 3
    or v_a_total <> 30000000
    or v_b_total <> 30000000
    or v_release_count <> 3
    or v_financial_count <> 3
    or v_audit_count <> 1 then
    raise exception 'retirement release did not pay each receivable owner exactly once';
  end if;
end;
$$;

-- Released correction applies append-only deltas, including downwards and zero.
select set_config('test.retirement.release_result_id', (
  select result.id::text
  from public.race_results as result
  where result.horse_id = '00000000-0000-0000-0000-00000000e303'
    and result.finish_position = 1
    and result.status = 'CONFIRMED'
), true);
select set_config('test.retirement.release_actual_id', (
  select actual_race_id::text from public.race_results
  where id = current_setting('test.retirement.release_result_id', true)::uuid
), true);
select public.correct_race_result(
  current_setting('test.retirement.release_result_id', true)::uuid,
  current_setting('test.retirement.release_actual_id', true)::uuid,
  1::smallint, 50000000::bigint, null, null, null, 'increase released prize'
);
select public.correct_race_result(
  current_setting('test.retirement.release_result_id', true)::uuid,
  current_setting('test.retirement.release_actual_id', true)::uuid,
  1::smallint, 30000000::bigint, null, null, null, 'decrease released prize'
);
select public.correct_race_result(
  current_setting('test.retirement.release_result_id', true)::uuid,
  current_setting('test.retirement.release_actual_id', true)::uuid,
  1::smallint, 0::bigint, null, null, null, 'reduce released prize to zero'
);

do $$
begin
  if (select coalesce(sum(ledger_entry.amount_delta), 0)
      from public.prize_receivable_ledger_entries as ledger_entry
      join public.prize_receivables as receivable on receivable.id = ledger_entry.prize_receivable_id
      where receivable.race_result_id = current_setting('test.retirement.release_result_id', true)::uuid) <> 0
    or (select amount from public.prize_receivables
        where race_result_id = current_setting('test.retirement.release_result_id', true)::uuid) <> 0
    or (select count(*) from public.financial_transactions where transaction_kind = 'PRIZE_CORRECTION') <> 3 then
    raise exception 'released prize correction deltas are not append-only or do not net to current amount';
  end if;
end;
$$;

-- A released prize void reverses its remaining amount exactly once; a zero
-- remaining prize deliberately receives a zero ledger link and no financial row.
select public.void_race_result(current_setting('test.retirement.release_result_id', true)::uuid, 'void released zero prize');
do $$
begin
  if not exists (
    select 1 from public.prize_receivables
    where race_result_id = current_setting('test.retirement.release_result_id', true)::uuid
      and status = 'CANCELLED'::public.prize_receivable_status
      and released_at is not null
  ) or not exists (
    select 1 from public.prize_receivable_ledger_entries as ledger_entry
    join public.prize_receivables as receivable on receivable.id = ledger_entry.prize_receivable_id
    where receivable.race_result_id = current_setting('test.retirement.release_result_id', true)::uuid
      and ledger_entry.entry_kind = 'VOID_REVERSAL'
      and ledger_entry.amount_delta = 0
      and ledger_entry.financial_transaction_id is null
  ) then
    raise exception 'released zero prize void did not retain an auditable zero reversal';
  end if;
end;
$$;

-- A voided Result can be re-recorded after retirement; the new Receivable must
-- be released within the record transaction rather than remaining pending.
select public.record_race_result(
  (select confirmed_race_entry_id from public.race_results where id = current_setting('test.retirement.release_result_id', true)::uuid),
  current_setting('test.retirement.release_actual_id', true)::uuid,
  1::smallint, 15000000::bigint, null, null, null
);
do $$
begin
  if exists (
    select 1 from public.prize_receivables
    where horse_id = '00000000-0000-0000-0000-00000000e303'
      and status = 'PENDING'::public.prize_receivable_status
  ) or not exists (
    select 1 from public.prize_receivables
    where horse_id = '00000000-0000-0000-0000-00000000e303'
      and amount = 15000000
      and status = 'RELEASED'::public.prize_receivable_status
  ) then
    raise exception 'late/re-recorded result on a retired Horse was not immediately released';
  end if;
end;
$$;

-- Zero prize release creates an exactly-once release ledger fact without an
-- invalid zero financial transaction.
select public.create_gm_confirmed_race_entry(
  '00000000-0000-0000-0000-00000000e306', 2040, 12::smallint, 5::smallint,
  'CATALOG'::public.race_entry_race_kind, '00000000-0000-0000-0000-00000000e401', null, null, null, null
);
select public.record_race_result(
  (select id from public.confirmed_race_entries where horse_id = '00000000-0000-0000-0000-00000000e306'),
  (select id from public.actual_races where race_catalog_id = '00000000-0000-0000-0000-00000000e401' and wp_week = 5),
  1::smallint, 0::bigint, null, null, null
);
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000e101', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('test.retirement.zero_request_id', (
  select id::text from public.submit_horse_retirement_request('00000000-0000-0000-0000-00000000e306', null)
), true);
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000e103', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select public.confirm_horse_retirement(current_setting('test.retirement.zero_request_id', true)::uuid);
do $$
begin
  if not exists (
    select 1 from public.prize_receivable_ledger_entries
    where retirement_request_id = current_setting('test.retirement.zero_request_id', true)::uuid
      and entry_kind = 'RELEASE'::public.prize_receivable_ledger_entry_kind
      and amount_delta = 0
      and financial_transaction_id is null
  ) then
    raise exception 'zero prize release lacks its zero ledger fact';
  end if;
end;
$$;

-- Pending void remains ledger-neutral.
-- This direct INSERT intentionally targets a non-retired horse row so it can
-- exercise the PENDING void branch without a release side effect.
insert into public.horses (
  id, horse_number, birth_year, foal_name, sex, coat_color,
  sire_name, sire_line, broodmare_sire_name, owner_id, life_stage
) values (
  '00000000-0000-0000-0000-00000000e308', 94108, 2036, 'Retirement Pending Prize', 'FEMALE', 'BAY', 'Sire 8', 'Line 8', 'Dam 8', '00000000-0000-0000-0000-00000000e201', 'ACTIVE'
);
select public.create_gm_confirmed_race_entry(
  '00000000-0000-0000-0000-00000000e308', 2040, 12::smallint, 5::smallint,
  'CATALOG'::public.race_entry_race_kind, '00000000-0000-0000-0000-00000000e401', null, null, null, null
);
select public.record_race_result(
  (select id from public.confirmed_race_entries where horse_id = '00000000-0000-0000-0000-00000000e308'),
  (select id from public.actual_races where race_catalog_id = '00000000-0000-0000-0000-00000000e401' and wp_month = 12 and wp_week = 5),
  2::smallint, 50000000::bigint, null, null, null
);
select set_config('test.retirement.pending_void_result_id', (
  select id::text from public.race_results where horse_id = '00000000-0000-0000-0000-00000000e308'
), true);
select public.void_race_result(current_setting('test.retirement.pending_void_result_id', true)::uuid, 'void pending prize');
do $$
begin
  if exists (
    select 1 from public.prize_receivable_ledger_entries as ledger_entry
    join public.prize_receivables as receivable on receivable.id = ledger_entry.prize_receivable_id
    where receivable.race_result_id = current_setting('test.retirement.pending_void_result_id', true)::uuid
  ) then
    raise exception 'pending prize void must not create a ledger entry';
  end if;
end;
$$;

-- Build exactly nine current G1 wins, prove G1_LIMIT succeeds, reject it, void
-- one winner, then prove the current effective count falls to eight.
reset role;
select set_config('horserpg.gm_direct_race_entry', 'on', true);
insert into public.confirmed_race_entries (
  horse_id, owner_id, wp_year, wp_month, wp_week, race_kind, race_catalog_id, confirmed_by_user_id
)
select
  '00000000-0000-0000-0000-00000000e305',
  '00000000-0000-0000-0000-00000000e201',
  2040, generated.month_number::smallint, 1::smallint,
  'CATALOG'::public.race_entry_race_kind,
  '00000000-0000-0000-0000-00000000e402',
  '00000000-0000-0000-0000-00000000e103'
from generate_series(1, 9) as generated(month_number);
insert into public.actual_races (
  wp_year, wp_month, wp_week, race_kind, race_catalog_id, race_name, grade, created_by_user_id
)
select
  2040, generated.month_number::smallint, 1::smallint,
  'CATALOG'::public.race_entry_race_kind,
  '00000000-0000-0000-0000-00000000e402',
  'Retirement Test G1', 'G1'::public.race_catalog_grade,
  '00000000-0000-0000-0000-00000000e103'
from generate_series(1, 9) as generated(month_number);
insert into public.race_results (
  confirmed_race_entry_id, actual_race_id, horse_id, finish_position, prize_amount, recorded_by_user_id
)
select
  entry.id, actual_race.id, entry.horse_id, 1::smallint, 0::bigint,
  '00000000-0000-0000-0000-00000000e103'
from public.confirmed_race_entries as entry
join public.actual_races as actual_race
  on actual_race.wp_year = entry.wp_year
 and actual_race.wp_month = entry.wp_month
 and actual_race.wp_week = entry.wp_week
 and actual_race.race_catalog_id = entry.race_catalog_id
where entry.horse_id = '00000000-0000-0000-0000-00000000e305';
select set_config('test.retirement.g1_request_id', (
  select id::text from public.create_gm_retirement_request(
    '00000000-0000-0000-0000-00000000e305',
    'G1_LIMIT'::public.horse_retirement_request_kind,
    null
  )
), true);
select public.reject_horse_retirement_request(current_setting('test.retirement.g1_request_id', true)::uuid, 'G1 test cleanup');
select set_config('test.retirement.g1_result_to_void', (
  select id::text from public.race_results
  where horse_id = '00000000-0000-0000-0000-00000000e305'
  order by id limit 1
), true);
select public.void_race_result(current_setting('test.retirement.g1_result_to_void', true)::uuid, 'void one G1 win');
do $$
begin
  begin
    perform public.create_gm_retirement_request(
      '00000000-0000-0000-0000-00000000e305',
      'G1_LIMIT'::public.horse_retirement_request_kind,
      null
    );
    raise exception 'G1_LIMIT should fail after one of nine wins is voided';
  exception when sqlstate '23514' then null;
  end;
end;
$$;

-- Inject a local test-only second-release failure.  The complete confirm call
-- must roll back Horse, Request, receipts, ledger, financial rows, and audit.
create function public.test_retirement_fail_selected_release()
returns trigger
language plpgsql
as $$
begin
  if new.entry_kind = 'RELEASE'::public.prize_receivable_ledger_entry_kind
    and new.prize_receivable_id::text = current_setting('test.retirement.fail_receivable_id', true) then
    raise exception 'intentional retirement release test failure';
  end if;
  return new;
end;
$$;
create trigger test_retirement_fail_selected_release
before insert on public.prize_receivable_ledger_entries
for each row execute function public.test_retirement_fail_selected_release();

-- Use two zero-value pending rows to isolate atomicity from funds assertions.
reset role;
insert into public.confirmed_race_entries (
  horse_id, owner_id, wp_year, wp_month, wp_week, race_kind, race_catalog_id, confirmed_by_user_id
) values
  ('00000000-0000-0000-0000-00000000e307', '00000000-0000-0000-0000-00000000e201', 2040, 10, 1, 'CATALOG', '00000000-0000-0000-0000-00000000e401', '00000000-0000-0000-0000-00000000e103'),
  ('00000000-0000-0000-0000-00000000e307', '00000000-0000-0000-0000-00000000e201', 2040, 10, 2, 'CATALOG', '00000000-0000-0000-0000-00000000e401', '00000000-0000-0000-0000-00000000e103');
insert into public.actual_races (
  wp_year, wp_month, wp_week, race_kind, race_catalog_id, race_name, grade, created_by_user_id
) values
  (2040, 10, 1, 'CATALOG', '00000000-0000-0000-0000-00000000e401', 'Retirement Test G2', 'G2', '00000000-0000-0000-0000-00000000e103'),
  (2040, 10, 2, 'CATALOG', '00000000-0000-0000-0000-00000000e401', 'Retirement Test G2', 'G2', '00000000-0000-0000-0000-00000000e103');
insert into public.race_results (
  confirmed_race_entry_id, actual_race_id, horse_id, finish_position, prize_amount, recorded_by_user_id
)
select entry.id, actual_race.id, entry.horse_id, 1, 0, '00000000-0000-0000-0000-00000000e103'
from public.confirmed_race_entries as entry
join public.actual_races as actual_race
  on actual_race.wp_year = entry.wp_year and actual_race.wp_month = entry.wp_month and actual_race.wp_week = entry.wp_week
where entry.horse_id = '00000000-0000-0000-0000-00000000e307';

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000e101', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('test.retirement.atomic_request_id', (
  select id::text from public.submit_horse_retirement_request('00000000-0000-0000-0000-00000000e307', null)
), true);
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000e103', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('test.retirement.fail_receivable_id', (
  select id::text from public.prize_receivables
  where horse_id = '00000000-0000-0000-0000-00000000e307'
  order by id desc limit 1
), true);
do $$
begin
  begin
    perform public.confirm_horse_retirement(current_setting('test.retirement.atomic_request_id', true)::uuid);
    raise exception 'intentional release failure should abort retirement confirmation';
  exception when others then
    if sqlerrm not like '%intentional retirement release test failure%' then
      raise;
    end if;
  end;

  if (select life_stage from public.horses where id = '00000000-0000-0000-0000-00000000e307')
      <> 'RETIRE_PENDING'::public.horse_life_stage
    or (select status from public.horse_retirement_requests where id = current_setting('test.retirement.atomic_request_id', true)::uuid)
      <> 'PENDING'::public.horse_retirement_request_status
    or exists (
      select 1 from public.prize_receivables
      where horse_id = '00000000-0000-0000-0000-00000000e307'
        and status <> 'PENDING'::public.prize_receivable_status
    ) then
    raise exception 'failed retirement confirmation leaked a partial business state';
  end if;
end;
$$;

-- Ledger release, correction, reversal, and late re-record naturally feed the
-- existing funds aggregation; retirement changes no freeze source.
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000e101', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
do $$
declare
  v_funds record;
begin
  select * into v_funds from public.get_current_owner_funds();
  if v_funds.account_funds <> 135000000
    or v_funds.foal_trade_frozen_funds <> 0
    or v_funds.available_funds <> 135000000 then
    raise exception 'prize ledger facts did not flow through the existing Owner funds calculation';
  end if;
end;
$$;

-- Auth deletion keeps retirement and prize-ledger history while nulling actors.
reset role;
insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-00000000e104', 'authenticated', 'authenticated', 'retirement-deleted-actor@example.test', 'not-used', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()
);
insert into public.horse_retirement_requests (
  horse_id, owner_id, request_kind, status, requested_by_user_id, requested_at, withdrawn_at
) values (
  '00000000-0000-0000-0000-00000000e302', '00000000-0000-0000-0000-00000000e201', 'OWNER_REQUEST', 'WITHDRAWN', '00000000-0000-0000-0000-00000000e104', clock_timestamp() - interval '1 hour', clock_timestamp()
);
delete from auth.users where id = '00000000-0000-0000-0000-00000000e104';
do $$
begin
  if not exists (
    select 1 from public.horse_retirement_requests
    where horse_id = '00000000-0000-0000-0000-00000000e302'
      and requested_by_user_id is null
  ) then
    raise exception 'Auth deletion did not preserve retirement history with null actor';
  end if;
end;
$$;

delete from auth.users where id = '00000000-0000-0000-0000-00000000e103';
do $$
begin
  if exists (
    select 1 from public.prize_receivable_ledger_entries
    where actor_user_id is not null
  ) or exists (
    select 1 from public.financial_transactions
    where source_entity_type = 'PRIZE_RECEIVABLE_LEDGER_ENTRY'
      and created_by_user_id is not null
  ) or exists (
    select 1 from public.audit_logs
    where action in (
      'HORSE_RETIREMENT_CONFIRMED',
      'PRIZE_RECEIVABLE_RELEASED',
      'PRIZE_RECEIVABLE_RELEASE_ADJUSTED',
      'PRIZE_RECEIVABLE_RELEASE_REVERSED'
    ) and actor_user_id is not null
  ) then
    raise exception 'Auth deletion did not preserve prize/financial/audit history with null actors';
  end if;
end;
$$;

rollback;
