-- Local-only verification for 20260814160000_create_core_schema_v0_1.sql.
-- Run this against a local Supabase/PostgreSQL database as a privileged database
-- role after applying the migration. It creates genuine local auth.users fixtures,
-- then switches to authenticated JWT contexts for PLAYER and GM RLS assertions.
-- This file starts a transaction and ends with ROLLBACK; it must never be run
-- against a remote or production database.

begin;

do $$
declare
  required_tables text[] := array[
    'user_profiles',
    'owners',
    'horses',
    'horse_factors',
    'financial_transactions',
    'injuries',
    'condition_records',
    'audit_logs',
    'game_state'
  ];
  required_table_name text;
  column_type text;
begin
  foreach required_table_name in array required_tables loop
    if not exists (
      select 1
      from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'public'
        and c.relname = required_table_name
        and c.relrowsecurity
    ) then
      raise exception 'RLS is not enabled for public.%', required_table_name;
    end if;
  end loop;

  select data_type
  into column_type
  from information_schema.columns as columns_info
  where columns_info.table_schema = 'public'
    and columns_info.table_name = 'owners'
    and columns_info.column_name = 'initial_funds';

  if column_type <> 'bigint' then
    raise exception 'owners.initial_funds must be bigint, got %', column_type;
  end if;

  select data_type
  into column_type
  from information_schema.columns as columns_info
  where columns_info.table_schema = 'public'
    and columns_info.table_name = 'financial_transactions'
    and columns_info.column_name = 'amount';

  if column_type <> 'bigint' then
    raise exception 'financial_transactions.amount must be bigint, got %', column_type;
  end if;

  select data_type
  into column_type
  from information_schema.columns as columns_info
  where columns_info.table_schema = 'public'
    and columns_info.table_name = 'audit_logs'
    and columns_info.column_name = 'entity_id';

  if column_type <> 'text' then
    raise exception 'audit_logs.entity_id must be text, got %', column_type;
  end if;

  if not exists (
    select 1
    from pg_indexes
    where schemaname = 'public'
      and tablename = 'horses'
      and indexdef like '%UNIQUE%horse_number%'
  ) then
    raise exception 'horses.horse_number has no unique index';
  end if;

  if not exists (
    select 1
    from pg_indexes
    where schemaname = 'public'
      and indexname = 'user_profiles_one_player_per_owner_idx'
  ) then
    raise exception 'one PLAYER per Owner index is missing';
  end if;
end;
$$;

insert into auth.users (
  instance_id,
  id,
  aud,
  role,
  email,
  encrypted_password,
  email_confirmed_at,
  raw_app_meta_data,
  raw_user_meta_data,
  created_at,
  updated_at
)
values
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000000301', 'authenticated', 'authenticated', 'core-player@example.test', 'not-used', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000000302', 'authenticated', 'authenticated', 'core-gm@example.test', 'not-used', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000000303', 'authenticated', 'authenticated', 'core-second-player@example.test', 'not-used', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000000304', 'authenticated', 'authenticated', 'core-player-without-owner@example.test', 'not-used', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000000305', 'authenticated', 'authenticated', 'core-gm-with-owner@example.test', 'not-used', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000000306', 'authenticated', 'authenticated', 'core-deleted-actor@example.test', 'not-used', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now());

insert into public.owners (id, display_name, initial_funds)
values
  ('00000000-0000-0000-0000-000000000101', 'Test Owner A', 1000000),
  ('00000000-0000-0000-0000-000000000102', 'Test Owner B', 1000000);

insert into public.horses (
  id,
  horse_number,
  birth_year,
  foal_name,
  sex,
  coat_color,
  sire_name,
  sire_line,
  broodmare_sire_name
)
values (
  '00000000-0000-0000-0000-000000000201',
  10001,
  2026,
  'Test Foal',
  'MALE',
  'BAY',
  'Test Sire',
  'Test Sire Line',
  'Test Broodmare Sire'
);

do $$
begin
  begin
    insert into public.horses (
      horse_number,
      birth_year,
      foal_name,
      sex,
      coat_color,
      sire_name,
      sire_line,
      broodmare_sire_name
    )
    values (10001, 2026, 'Duplicate Number', 'FEMALE', 'BAY', 'Sire', 'Line', 'Broodmare Sire');
    raise exception 'duplicate horse_number was accepted';
  exception
    when unique_violation then null;
  end;
end;
$$;

insert into public.horse_factors (horse_id, factor_kind, factor_name)
values
  ('00000000-0000-0000-0000-000000000201', 'SIRE', 'Sire Factor One'),
  ('00000000-0000-0000-0000-000000000201', 'SIRE', 'Sire Factor Two'),
  ('00000000-0000-0000-0000-000000000201', 'MARE', 'Mare Factor One'),
  ('00000000-0000-0000-0000-000000000201', 'MARE', 'Mare Factor Two');

do $$
begin
  begin
    insert into public.horse_factors (horse_id, factor_kind, factor_name)
    values ('00000000-0000-0000-0000-000000000201', 'SIRE', 'Sire Factor Three');
    raise exception 'third factor of one kind was accepted';
  exception
    when check_violation then null;
  end;

  begin
    insert into public.horse_factors (horse_id, factor_kind, factor_name)
    values ('00000000-0000-0000-0000-000000000201', 'MARE', 'Mare Factor Three');
    raise exception 'third MARE factor was accepted';
  exception
    when check_violation then null;
  end;

  begin
    insert into public.injuries (
      horse_id,
      status,
      wp_start_year,
      wp_start_month,
      wp_start_week,
      wp_end_year,
      wp_end_month,
      wp_end_week
    )
    values ('00000000-0000-0000-0000-000000000201', 'ACTIVE', 2026, 13, 1, 2026, 13, 1);
    raise exception 'invalid WP month was accepted';
  exception
    when check_violation then null;
  end;

  begin
    insert into public.injuries (
      horse_id,
      status,
      wp_start_year,
      wp_start_month,
      wp_start_week,
      wp_end_year,
      wp_end_month,
      wp_end_week
    )
    values ('00000000-0000-0000-0000-000000000201', 'ACTIVE', 2026, 2, 1, 2026, 1, 5);
    raise exception 'injury ending before its start was accepted';
  exception
    when check_violation then null;
  end;

  begin
    insert into public.condition_records (horse_id, wp_year, wp_month, wp_week, outcome)
    values ('00000000-0000-0000-0000-000000000201', 2026, 1, 6, '{}'::jsonb);
    raise exception 'invalid WP week was accepted';
  exception
    when check_violation then null;
  end;

  begin
    update public.owners
    set initial_funds = initial_funds + 1
    where id = '00000000-0000-0000-0000-000000000101';
    raise exception 'initial_funds update was accepted';
  exception
    when check_violation then null;
  end;
end;
$$;

update public.horses
set owner_id = '00000000-0000-0000-0000-000000000101'
where id = '00000000-0000-0000-0000-000000000201';

insert into public.financial_transactions (owner_id, amount, transaction_kind, created_by_user_id)
values ('00000000-0000-0000-0000-000000000101', 500, 'TEST_SEED', '00000000-0000-0000-0000-000000000306');

insert into public.injuries (
  id,
  horse_id,
  status,
  wp_start_year,
  wp_start_month,
  wp_start_week,
  wp_end_year,
  wp_end_month,
  wp_end_week
)
values (
  '00000000-0000-0000-0000-000000000401',
  '00000000-0000-0000-0000-000000000201',
  'ACTIVE',
  2026,
  1,
  1,
  2026,
  2,
  1
);

update public.injuries
set status = 'RECOVERED'
where id = '00000000-0000-0000-0000-000000000401';

do $$
begin
  if not exists (
    select 1
    from public.injuries
    where id = '00000000-0000-0000-0000-000000000401'
      and status = 'RECOVERED'
      and (wp_start_year, wp_start_month, wp_start_week) = (2026, 1, 1)
      and (wp_end_year, wp_end_month, wp_end_week) = (2026, 2, 1)
  ) then
    raise exception 'recovered injury did not retain its WP history';
  end if;
end;
$$;

insert into public.condition_records (horse_id, wp_year, wp_month, wp_week, outcome)
values ('00000000-0000-0000-0000-000000000201', 2026, 1, 1, '{"stamina": "GM_ONLY"}'::jsonb);

do $$
begin
  begin
    update public.horses
    set owner_id = '00000000-0000-0000-0000-000000000102'
    where id = '00000000-0000-0000-0000-000000000201';
    raise exception 'direct horse ownership transfer was accepted';
  exception
    when check_violation then null;
  end;
end;
$$;

insert into public.user_profiles (id, role, owner_id)
values
  ('00000000-0000-0000-0000-000000000301', 'PLAYER', '00000000-0000-0000-0000-000000000101'),
  ('00000000-0000-0000-0000-000000000302', 'GM', null);

insert into public.audit_logs (
  actor_user_id,
  actor_role,
  action,
  entity_type,
  entity_id,
  after_data
)
values (
  '00000000-0000-0000-0000-000000000306',
  'GM',
  'TEST_ACTION',
  'TEST_ENTITY',
  'game_state:current',
  '{}'::jsonb
);

do $$
begin
  begin
    insert into public.user_profiles (id, role, owner_id)
    values ('00000000-0000-0000-0000-000000000303', 'PLAYER', null);
    raise exception 'PLAYER profile without owner_id was accepted';
  exception
    when check_violation then null;
  end;

  begin
    insert into public.user_profiles (id, role, owner_id)
    values ('00000000-0000-0000-0000-000000000304', 'GM', '00000000-0000-0000-0000-000000000101');
    raise exception 'GM profile with owner_id was accepted';
  exception
    when check_violation then null;
  end;

  begin
    insert into public.user_profiles (id, role, owner_id)
    values ('00000000-0000-0000-0000-000000000305', 'PLAYER', '00000000-0000-0000-0000-000000000101');
    raise exception 'second PLAYER profile for an Owner was accepted';
  exception
    when unique_violation then null;
  end;
end;
$$;

do $$
begin
  begin
    update public.financial_transactions
    set amount = 600
    where transaction_kind = 'TEST_SEED';
    raise exception 'financial transaction update was accepted';
  exception
    when object_not_in_prerequisite_state then null;
  end;

  begin
    delete from public.financial_transactions
    where transaction_kind = 'TEST_SEED';
    raise exception 'financial transaction delete was accepted';
  exception
    when object_not_in_prerequisite_state then null;
  end;

  begin
    update public.audit_logs
    set action = 'MUTATED'
    where action = 'TEST_ACTION';
    raise exception 'audit log update was accepted';
  exception
    when object_not_in_prerequisite_state then null;
  end;

  begin
    delete from public.audit_logs
    where action = 'TEST_ACTION';
    raise exception 'audit log delete was accepted';
  exception
    when object_not_in_prerequisite_state then null;
  end;
end;
$$;

-- ON DELETE SET NULL must retain ledger and audit facts without weakening their
-- append-only trigger for ordinary UPDATE or DELETE statements.
delete from auth.users
where id = '00000000-0000-0000-0000-000000000306';

do $$
begin
  if not exists (
    select 1
    from public.financial_transactions
    where transaction_kind = 'TEST_SEED'
      and created_by_user_id is null
  ) then
    raise exception 'Auth deletion did not retain the financial transaction and null its actor';
  end if;

  if not exists (
    select 1
    from public.audit_logs
    where action = 'TEST_ACTION'
      and actor_user_id is null
      and entity_id = 'game_state:current'
  ) then
    raise exception 'Auth deletion did not retain the audit log and null its actor';
  end if;
end;
$$;

-- Initialize the singleton through the real local GM RLS context, not as the
-- privileged migration runner.
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000302', true);
select set_config('request.jwt.claim.role', 'authenticated', true);

insert into public.game_state (current_wp_year, current_wp_month, current_wp_week)
values (2026, 1, 1);

reset role;

-- The real local PLAYER Auth fixture can read public records but cannot inspect
-- audit or condition entries, append a ledger fact, or delete a horse factor.
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000301', true);
select set_config('request.jwt.claim.role', 'authenticated', true);

do $$
declare
  visible_horses integer;
  visible_audit_logs integer;
  visible_condition_records integer;
  visible_game_state integer;
begin
  select count(*) into visible_horses from public.horses;
  if visible_horses <> 1 then
    raise exception 'PLAYER could not read the expected public horse record';
  end if;

  select count(*) into visible_audit_logs from public.audit_logs;
  if visible_audit_logs <> 0 then
    raise exception 'PLAYER could read audit_logs';
  end if;

  select count(*) into visible_condition_records from public.condition_records;
  if visible_condition_records <> 0 then
    raise exception 'PLAYER could read condition_records';
  end if;

  select count(*) into visible_game_state from public.game_state;
  if visible_game_state <> 1 then
    raise exception 'PLAYER could not read game_state';
  end if;

  begin
    insert into public.financial_transactions (owner_id, amount, transaction_kind)
    values ('00000000-0000-0000-0000-000000000101', 1, 'TEST_DIRECT_WRITE');
    raise exception 'PLAYER directly created a financial transaction';
  exception
    when insufficient_privilege then null;
  end;

  update public.injuries
  set status = 'CANCELLED'
  where id = '00000000-0000-0000-0000-000000000401';

  if found then
    raise exception 'PLAYER directly updated an injury';
  end if;

  update public.condition_records
  set notes = 'PLAYER_WRITE'
  where horse_id = '00000000-0000-0000-0000-000000000201';

  if found then
    raise exception 'PLAYER directly updated a condition record';
  end if;

  update public.game_state
  set current_wp_week = 3;

  if found then
    raise exception 'PLAYER directly updated game_state';
  end if;

  delete from public.horse_factors
  where factor_name = 'Sire Factor One';

  if found then
    raise exception 'PLAYER deleted a horse factor';
  end if;
end;
$$;

reset role;

-- The real local GM Auth fixture can inspect GM-only data, create and update the
-- singleton game state, and delete an incorrectly recorded horse factor.
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000302', true);
select set_config('request.jwt.claim.role', 'authenticated', true);

do $$
declare
  visible_audit_logs integer;
  visible_transactions integer;
  visible_condition_records integer;
begin
  select count(*) into visible_audit_logs from public.audit_logs;
  if visible_audit_logs <> 1 then
    raise exception 'GM could not read audit_logs';
  end if;

  select count(*) into visible_transactions from public.financial_transactions;
  if visible_transactions <> 1 then
    raise exception 'GM could not read financial_transactions';
  end if;

  select count(*) into visible_condition_records from public.condition_records;
  if visible_condition_records <> 1 then
    raise exception 'GM could not read condition_records';
  end if;

  begin
    insert into public.game_state (current_wp_year, current_wp_month, current_wp_week)
    values (2026, 1, 2);
    raise exception 'GM created a second game_state row';
  exception
    when unique_violation then null;
  end;

  begin
    update public.game_state
    set current_wp_month = 13;
    raise exception 'GM accepted an invalid game_state WP month';
  exception
    when check_violation then null;
  end;

  delete from public.horse_factors
  where factor_name = 'Sire Factor Two';

  if not found then
    raise exception 'GM could not delete a horse factor';
  end if;

  update public.game_state
  set current_wp_week = 2;
end;
$$;

reset role;
rollback;
