-- Local-only verification for 20260814220000_add_current_owner_funds_rpc.sql.
-- Run after `supabase db reset`. This test rolls its fixtures back and must
-- never run against a remote or production database.

begin;

do $$
begin
  if not exists (
    select 1
    from pg_proc as procedure
    join pg_namespace as namespace on namespace.oid = procedure.pronamespace
    where namespace.nspname = 'public'
      and procedure.oid = 'public.get_current_owner_funds()'::regprocedure
  ) then
    raise exception 'get_current_owner_funds() does not exist';
  end if;

  if not has_function_privilege(
    'authenticated',
    'public.get_current_owner_funds()'::regprocedure,
    'EXECUTE'
  )
  or has_function_privilege(
    'anon',
    'public.get_current_owner_funds()'::regprocedure,
    'EXECUTE'
  )
  or has_function_privilege(
    'service_role',
    'public.get_current_owner_funds()'::regprocedure,
    'EXECUTE'
  ) then
    raise exception 'get_current_owner_funds() execute ACL is incorrect';
  end if;
end;
$$;

-- Unauthenticated and service-role calls have no execute grant. The latter is
-- intentional: server-only code has no business need to call this PLAYER RPC.
set local role anon;
do $$
begin
  begin
    perform public.get_current_owner_funds();
    raise exception 'anon invoked get_current_owner_funds()' using errcode = 'XX000';
  exception
    when insufficient_privilege then null;
  end;
end;
$$;
reset role;

set local role service_role;
do $$
begin
  begin
    perform public.get_current_owner_funds();
    raise exception 'service_role invoked get_current_owner_funds()' using errcode = 'XX000';
  exception
    when insufficient_privilege then null;
  end;
end;
$$;
reset role;

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
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000002201', 'authenticated', 'authenticated', 'funds-player-a@example.test', 'not-used', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000002202', 'authenticated', 'authenticated', 'funds-player-b@example.test', 'not-used', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000002203', 'authenticated', 'authenticated', 'funds-gm@example.test', 'not-used', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000002204', 'authenticated', 'authenticated', 'funds-unbound@example.test', 'not-used', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now());

insert into public.owners (id, display_name, initial_funds)
values
  ('00000000-0000-0000-0000-000000002101', 'Funds Owner A', 50000000),
  ('00000000-0000-0000-0000-000000002102', 'Funds Owner B', 50000000);

insert into public.user_profiles (id, role, owner_id, display_name)
values
  ('00000000-0000-0000-0000-000000002201', 'PLAYER', '00000000-0000-0000-0000-000000002101', 'Funds Player A'),
  ('00000000-0000-0000-0000-000000002202', 'PLAYER', '00000000-0000-0000-0000-000000002102', 'Funds Player B'),
  ('00000000-0000-0000-0000-000000002203', 'GM', null, 'Funds GM');

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
values
  ('00000000-0000-0000-0000-000000002301', 42201, 2042, 'Funds Foal One', 'MALE', 'BAY', 'Funds Sire One', 'Funds Line One', 'Funds Broodmare One'),
  ('00000000-0000-0000-0000-000000002302', 42202, 2042, 'Funds Foal Two', 'FEMALE', 'CHESTNUT', 'Funds Sire Two', 'Funds Line Two', 'Funds Broodmare Two');

insert into public.foal_trade_sessions (id, wp_year, starts_at, ends_at, status)
values (
  '00000000-0000-0000-0000-000000002401',
  2042,
  clock_timestamp() - interval '1 hour',
  clock_timestamp() + interval '1 hour',
  'OPEN'
);

insert into public.foal_trade_lots (id, session_id, horse_id, minimum_price)
values
  ('00000000-0000-0000-0000-000000002501', '00000000-0000-0000-0000-000000002401', '00000000-0000-0000-0000-000000002301', 0),
  ('00000000-0000-0000-0000-000000002502', '00000000-0000-0000-0000-000000002401', '00000000-0000-0000-0000-000000002302', 0);

-- PLAYER A initially sees only their own 50m Owner funds.
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000002201', true);
select set_config('request.jwt.claim.role', 'authenticated', true);

do $$
declare
  v_account bigint;
  v_frozen bigint;
  v_available bigint;
begin
  select account_funds, foal_trade_frozen_funds, available_funds
  into v_account, v_frozen, v_available
  from public.get_current_owner_funds();

  if v_account <> 50000000 or v_frozen <> 0 or v_available <> 50000000 then
    raise exception 'PLAYER A initial fund summary is incorrect: %, %, %', v_account, v_frozen, v_available;
  end if;
end;
$$;
reset role;

-- A controlled ledger correction reduces A's account funds to 45m.
insert into public.financial_transactions (
  owner_id,
  amount,
  transaction_kind,
  source_entity_type,
  source_entity_id,
  created_by_user_id,
  reason
)
values (
  '00000000-0000-0000-0000-000000002101',
  -5000000,
  'GM_CORRECTION',
  'LOCAL_FUNDS_TEST',
  '00000000-0000-0000-0000-000000002401',
  '00000000-0000-0000-0000-000000002203',
  'Local funds RPC test correction'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000002201', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select public.submit_foal_trade_secret_bid('00000000-0000-0000-0000-000000002501', 20000000);
select public.submit_foal_trade_secret_bid('00000000-0000-0000-0000-000000002502', 10000000);

do $$
declare
  v_account bigint;
  v_frozen bigint;
  v_available bigint;
begin
  select account_funds, foal_trade_frozen_funds, available_funds
  into v_account, v_frozen, v_available
  from public.get_current_owner_funds();

  if v_account <> 45000000 or v_frozen <> 30000000 or v_available <> 15000000 then
    raise exception 'ACTIVE bid freeze summary is incorrect: %, %, %', v_account, v_frozen, v_available;
  end if;
end;
$$;
reset role;

-- B has a lower bid on Lot One. This later verifies a failed offer is released
-- and that B can never receive A's summary from the zero-argument RPC.
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000002202', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select public.submit_foal_trade_secret_bid('00000000-0000-0000-0000-000000002501', 15000000);
reset role;

-- A withdraws Lot Two, releasing it, then reactivates it before the deadline.
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000002201', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select public.withdraw_foal_trade_secret_bid('00000000-0000-0000-0000-000000002502');

do $$
declare
  v_account bigint;
  v_frozen bigint;
  v_available bigint;
begin
  select account_funds, foal_trade_frozen_funds, available_funds
  into v_account, v_frozen, v_available
  from public.get_current_owner_funds();

  if v_account <> 45000000 or v_frozen <> 20000000 or v_available <> 25000000 then
    raise exception 'withdrawn bid remains frozen: %, %, %', v_account, v_frozen, v_available;
  end if;
end;
$$;

select public.submit_foal_trade_secret_bid('00000000-0000-0000-0000-000000002502', 10000000);
reset role;

-- The server-side deadline does not release valid ACTIVE bids before GM
-- settlement, even though bid mutation RPCs no longer accept changes.
update public.foal_trade_sessions
set ends_at = clock_timestamp() - interval '1 second'
where id = '00000000-0000-0000-0000-000000002401';

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000002201', true);
select set_config('request.jwt.claim.role', 'authenticated', true);

do $$
declare
  v_frozen bigint;
begin
  select foal_trade_frozen_funds
  into v_frozen
  from public.get_current_owner_funds();

  if v_frozen <> 30000000 then
    raise exception 'deadline incorrectly released ACTIVE bids before settlement: %', v_frozen;
  end if;
end;
$$;
reset role;

-- Normal GM settlement debits A once, changes Lot One offers to WON/LOST, and
-- leaves only A's remaining Lot Two ACTIVE bid frozen.
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000002203', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select public.settle_foal_trade_lot('00000000-0000-0000-0000-000000002501', 'Local funds RPC settlement');

do $$
begin
  begin
    perform public.get_current_owner_funds();
    raise exception 'GM invoked the PLAYER funds RPC' using errcode = 'XX000';
  exception
    when insufficient_privilege then null;
  end;
end;
$$;
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000002201', true);
select set_config('request.jwt.claim.role', 'authenticated', true);

do $$
declare
  v_account bigint;
  v_frozen bigint;
  v_available bigint;
begin
  select account_funds, foal_trade_frozen_funds, available_funds
  into v_account, v_frozen, v_available
  from public.get_current_owner_funds();

  if v_account <> 25000000 or v_frozen <> 10000000 or v_available <> 15000000 then
    raise exception 'settled winning bid was double-counted as frozen: %, %, %', v_account, v_frozen, v_available;
  end if;
end;
$$;
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000002202', true);
select set_config('request.jwt.claim.role', 'authenticated', true);

do $$
declare
  v_account bigint;
  v_frozen bigint;
  v_available bigint;
begin
  select account_funds, foal_trade_frozen_funds, available_funds
  into v_account, v_frozen, v_available
  from public.get_current_owner_funds();

  if v_account <> 50000000 or v_frozen <> 0 or v_available <> 50000000 then
    raise exception 'PLAYER B saw non-private or failed-offer funds: %, %, %', v_account, v_frozen, v_available;
  end if;
end;
$$;
reset role;

-- A genuine authenticated account without a valid PLAYER profile is rejected.
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000002204', true);
select set_config('request.jwt.claim.role', 'authenticated', true);

do $$
begin
  begin
    perform public.get_current_owner_funds();
    raise exception 'unbound authenticated user invoked the PLAYER funds RPC' using errcode = 'XX000';
  exception
    when insufficient_privilege then null;
  end;
end;
$$;
reset role;

rollback;
