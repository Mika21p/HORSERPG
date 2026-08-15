-- Local-only verification for 20260814200000_create_foal_trade_schema_v0_2.sql.
-- Run only against the local Supabase database after `supabase db reset`.
-- The test creates genuine local auth.users fixtures and switches to real
-- authenticated JWT contexts. It ends with ROLLBACK and never targets remote.

begin;

do $$
declare
  required_tables text[] := array[
    'foal_trade_sessions',
    'foal_trade_lots',
    'foal_trade_inquiries',
    'secret_bid_offers',
    'secret_bid_offer_history',
    'foal_trade_settlements'
  ];
  required_table_name text;
  realtime_table_count integer;
begin
  foreach required_table_name in array required_tables loop
    if not exists (
      select 1
      from pg_class as c
      join pg_namespace as n on n.oid = c.relnamespace
      where n.nspname = 'public'
        and c.relname = required_table_name
        and c.relrowsecurity
    ) then
      raise exception 'RLS is not enabled for public.%', required_table_name;
    end if;
  end loop;

  select count(*)
  into realtime_table_count
  from pg_publication_tables
  where pubname = 'supabase_realtime'
    and schemaname = 'public'
    and tablename = any(required_tables);

  if realtime_table_count <> 0 then
    raise exception 'private foal-trade tables must not be added to Supabase Realtime';
  end if;

  if has_table_privilege('authenticated', 'public.secret_bid_offers', 'INSERT')
    or has_table_privilege('authenticated', 'public.secret_bid_offers', 'UPDATE')
    or has_table_privilege('authenticated', 'public.secret_bid_offers', 'DELETE') then
    raise exception 'authenticated must not receive direct secret bid write privileges';
  end if;
end;
$$;

-- 210000 hardens the final-result view and every foal-trade RPC ACL. The
-- view remains a security-definer projection for authenticated users only;
-- it is not made security_invoker because its source table is GM-only.
do $$
declare
  public_view_columns text[];
  protected_function_names text[] := array[
    'prevent_foal_trade_session_year_change',
    'enforce_foal_trade_lot_horse_eligibility',
    'prevent_foal_trade_minimum_price_conflict',
    'prevent_foal_trade_lot_horse_direct_assignment',
    'enforce_foal_trade_inquiry_integrity',
    'maintain_foal_trade_inquiry_answer_state',
    'enforce_secret_bid_offer_integrity',
    'enforce_secret_bid_offer_history_integrity',
    'prevent_secret_bid_offer_history_mutation',
    'enforce_foal_trade_settlement_integrity',
    'current_player_owner_id',
    'submit_foal_trade_secret_bid',
    'withdraw_foal_trade_secret_bid',
    'create_foal_trade_inquiry',
    'settle_foal_trade_lot_internal',
    'settle_foal_trade_lot',
    'settle_foal_trade_lot_override'
  ];
begin
  select array_agg(column_name order by ordinal_position)
  into public_view_columns
  from information_schema.columns
  where table_schema = 'public'
    and table_name = 'foal_trade_public_settlements';

  if public_view_columns is distinct from array[
    'lot_id',
    'session_id',
    'horse_id',
    'status',
    'winner_owner_id',
    'amount',
    'confirmed_at'
  ] then
    raise exception 'public settlement view exposes an unexpected column set: %', public_view_columns;
  end if;

  if has_table_privilege('anon', 'public.foal_trade_public_settlements', 'SELECT')
    or not has_table_privilege('authenticated', 'public.foal_trade_public_settlements', 'SELECT')
    or not has_table_privilege('service_role', 'public.foal_trade_public_settlements', 'SELECT')
    or has_table_privilege('authenticated', 'public.foal_trade_public_settlements', 'INSERT')
    or has_table_privilege('authenticated', 'public.foal_trade_public_settlements', 'UPDATE')
    or has_table_privilege('authenticated', 'public.foal_trade_public_settlements', 'DELETE')
    or has_table_privilege('service_role', 'public.foal_trade_public_settlements', 'INSERT')
    or has_table_privilege('service_role', 'public.foal_trade_public_settlements', 'UPDATE')
    or has_table_privilege('service_role', 'public.foal_trade_public_settlements', 'DELETE') then
    raise exception 'public settlement view ACL is not authenticated/service_role SELECT-only';
  end if;

  if has_function_privilege('anon', 'public.submit_foal_trade_secret_bid(uuid,bigint)'::regprocedure, 'EXECUTE')
    or has_function_privilege('anon', 'public.withdraw_foal_trade_secret_bid(uuid)'::regprocedure, 'EXECUTE')
    or has_function_privilege('anon', 'public.create_foal_trade_inquiry(uuid)'::regprocedure, 'EXECUTE')
    or has_function_privilege('anon', 'public.settle_foal_trade_lot(uuid,text)'::regprocedure, 'EXECUTE')
    or has_function_privilege('anon', 'public.settle_foal_trade_lot_override(uuid,uuid,text)'::regprocedure, 'EXECUTE')
    or has_function_privilege('anon', 'public.settle_foal_trade_lot_internal(uuid,uuid,text,text)'::regprocedure, 'EXECUTE')
    or has_function_privilege('authenticated', 'public.settle_foal_trade_lot_internal(uuid,uuid,text,text)'::regprocedure, 'EXECUTE')
    or has_function_privilege('service_role', 'public.settle_foal_trade_lot_internal(uuid,uuid,text,text)'::regprocedure, 'EXECUTE')
    or not has_function_privilege('authenticated', 'public.submit_foal_trade_secret_bid(uuid,bigint)'::regprocedure, 'EXECUTE')
    or not has_function_privilege('authenticated', 'public.withdraw_foal_trade_secret_bid(uuid)'::regprocedure, 'EXECUTE')
    or not has_function_privilege('authenticated', 'public.create_foal_trade_inquiry(uuid)'::regprocedure, 'EXECUTE')
    or not has_function_privilege('authenticated', 'public.settle_foal_trade_lot(uuid,text)'::regprocedure, 'EXECUTE')
    or not has_function_privilege('authenticated', 'public.settle_foal_trade_lot_override(uuid,uuid,text)'::regprocedure, 'EXECUTE') then
    raise exception 'foal-trade RPC execute ACL is incorrect';
  end if;

  -- The owner helper must remain executable by authenticated because the three
  -- Owner-private RLS policies call it. It is never exposed to anon or service.
  if not has_function_privilege('authenticated', 'public.current_player_owner_id()'::regprocedure, 'EXECUTE')
    or has_function_privilege('anon', 'public.current_player_owner_id()'::regprocedure, 'EXECUTE')
    or has_function_privilege('service_role', 'public.current_player_owner_id()'::regprocedure, 'EXECUTE') then
    raise exception 'current_player_owner_id ACL no longer supports RLS safely';
  end if;

  if exists (
    select 1
    from pg_proc as p
    join pg_namespace as n on n.oid = p.pronamespace
    cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) as acl
    where n.nspname = 'public'
      and p.proname = any(protected_function_names)
      and acl.grantee = 0
      and acl.privilege_type = 'EXECUTE'
  ) then
    raise exception 'a foal-trade function remains executable by PUBLIC';
  end if;

  if exists (
    select 1
    from pg_proc as p
    join pg_namespace as n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = any(array[
        'prevent_foal_trade_session_year_change',
        'enforce_foal_trade_lot_horse_eligibility',
        'prevent_foal_trade_minimum_price_conflict',
        'prevent_foal_trade_lot_horse_direct_assignment',
        'enforce_foal_trade_inquiry_integrity',
        'maintain_foal_trade_inquiry_answer_state',
        'enforce_secret_bid_offer_integrity',
        'enforce_secret_bid_offer_history_integrity',
        'prevent_secret_bid_offer_history_mutation',
        'enforce_foal_trade_settlement_integrity'
      ])
      and (
        has_function_privilege('anon', p.oid, 'EXECUTE')
        or has_function_privilege('authenticated', p.oid, 'EXECUTE')
        or has_function_privilege('service_role', p.oid, 'EXECUTE')
      )
  ) then
    raise exception 'a trigger-only foal-trade helper remains client-executable';
  end if;

  if exists (
    select 1
    from pg_default_acl as d
    join pg_roles as r on r.oid = d.defaclrole
    cross join lateral aclexplode(d.defaclacl) as acl
    where r.rolname = 'postgres'
      and d.defaclnamespace = 'public'::regnamespace
      and (
        (d.defaclobjtype = 'f' and acl.grantee = 0 and acl.privilege_type = 'EXECUTE')
        or (d.defaclobjtype = 'f' and acl.grantee = (select oid from pg_roles where rolname = 'anon') and acl.privilege_type = 'EXECUTE')
        or (d.defaclobjtype = 'r' and acl.grantee = (select oid from pg_roles where rolname = 'anon'))
      )
  ) then
    raise exception 'future public-schema default ACLs still expose a function or table to anon/PUBLIC';
  end if;
end;
$$;

-- An anonymous caller cannot query the result view or invoke any foal-trade
-- business/internal RPC. These checks use no business rows.
set local role anon;
do $$
begin
  begin
    perform 1 from public.foal_trade_public_settlements;
    raise exception 'anon selected the public settlement view' using errcode = 'XX000';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform public.submit_foal_trade_secret_bid('00000000-0000-0000-0000-000000000501', 0);
    raise exception 'anon invoked submit_foal_trade_secret_bid' using errcode = 'XX000';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform public.withdraw_foal_trade_secret_bid('00000000-0000-0000-0000-000000000501');
    raise exception 'anon invoked withdraw_foal_trade_secret_bid' using errcode = 'XX000';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform public.create_foal_trade_inquiry('00000000-0000-0000-0000-000000000501');
    raise exception 'anon invoked create_foal_trade_inquiry' using errcode = 'XX000';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform public.settle_foal_trade_lot('00000000-0000-0000-0000-000000000501', null);
    raise exception 'anon invoked settle_foal_trade_lot' using errcode = 'XX000';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform public.settle_foal_trade_lot_override(
      '00000000-0000-0000-0000-000000000501',
      null,
      'anon must not override'
    );
    raise exception 'anon invoked settle_foal_trade_lot_override' using errcode = 'XX000';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform public.settle_foal_trade_lot_internal(
      '00000000-0000-0000-0000-000000000501',
      null,
      null,
      null
    );
    raise exception 'anon invoked internal settlement implementation' using errcode = 'XX000';
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
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000000901', 'authenticated', 'authenticated', 'foal-a@example.test', 'not-used', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000000902', 'authenticated', 'authenticated', 'foal-b@example.test', 'not-used', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000000904', 'authenticated', 'authenticated', 'foal-c@example.test', 'not-used', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000000903', 'authenticated', 'authenticated', 'foal-gm@example.test', 'not-used', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now());

insert into public.owners (id, display_name, initial_funds)
values
  ('00000000-0000-0000-0000-000000000811', 'Foal Trade Owner A', 50000000),
  ('00000000-0000-0000-0000-000000000812', 'Foal Trade Owner B', 50000000),
  ('00000000-0000-0000-0000-000000000813', 'Foal Trade Owner C', 50000000);

insert into public.user_profiles (id, role, owner_id, display_name)
values
  ('00000000-0000-0000-0000-000000000901', 'PLAYER', '00000000-0000-0000-0000-000000000811', 'Foal Player A'),
  ('00000000-0000-0000-0000-000000000902', 'PLAYER', '00000000-0000-0000-0000-000000000812', 'Foal Player B'),
  ('00000000-0000-0000-0000-000000000904', 'PLAYER', '00000000-0000-0000-0000-000000000813', 'Foal Player C'),
  ('00000000-0000-0000-0000-000000000903', 'GM', null, 'Foal GM');

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
  ('00000000-0000-0000-0000-000000000701', 26001, 2026, 'Foal Trade Horse 1', 'MALE', 'BAY', 'Sire 1', 'Line 1', 'Broodmare Sire 1'),
  ('00000000-0000-0000-0000-000000000702', 26002, 2026, 'Foal Trade Horse 2', 'FEMALE', 'CHESTNUT', 'Sire 2', 'Line 2', 'Broodmare Sire 2'),
  ('00000000-0000-0000-0000-000000000703', 26003, 2026, 'Foal Trade Horse 3', 'MALE', 'BROWN', 'Sire 3', 'Line 3', 'Broodmare Sire 3'),
  ('00000000-0000-0000-0000-000000000704', 26004, 2026, 'Foal Trade Horse 4', 'FEMALE', 'GREY', 'Sire 4', 'Line 4', 'Broodmare Sire 4'),
  ('00000000-0000-0000-0000-000000000705', 26005, 2026, 'Foal Trade Horse 5', 'MALE', 'BAY', 'Sire 5', 'Line 5', 'Broodmare Sire 5'),
  ('00000000-0000-0000-0000-000000000706', 26006, 2025, 'Wrong Year Foal', 'MALE', 'BAY', 'Sire 6', 'Line 6', 'Broodmare Sire 6');

insert into public.foal_trade_sessions (id, wp_year, starts_at, ends_at, status)
values (
  '00000000-0000-0000-0000-000000000601',
  2026,
  clock_timestamp() - interval '1 hour',
  clock_timestamp() + interval '1 hour',
  'OPEN'
);

insert into public.foal_trade_lots (id, session_id, horse_id, minimum_price)
values
  ('00000000-0000-0000-0000-000000000501', '00000000-0000-0000-0000-000000000601', '00000000-0000-0000-0000-000000000701', 10000000),
  ('00000000-0000-0000-0000-000000000502', '00000000-0000-0000-0000-000000000601', '00000000-0000-0000-0000-000000000702', 10000000),
  ('00000000-0000-0000-0000-000000000503', '00000000-0000-0000-0000-000000000601', '00000000-0000-0000-0000-000000000703', 10000000),
  ('00000000-0000-0000-0000-000000000504', '00000000-0000-0000-0000-000000000601', '00000000-0000-0000-0000-000000000704', 10000000),
  ('00000000-0000-0000-0000-000000000505', '00000000-0000-0000-0000-000000000601', '00000000-0000-0000-0000-000000000705', 10000000);

do $$
begin
  begin
    insert into public.foal_trade_lots (session_id, horse_id, minimum_price)
    values ('00000000-0000-0000-0000-000000000601', '00000000-0000-0000-0000-000000000706', 10000000);
    raise exception 'wrong-year foal was accepted as a foal trade lot' using errcode = 'XX000';
  exception
    when check_violation then null;
  end;

  begin
    insert into public.foal_trade_lots (session_id, horse_id, minimum_price)
    values ('00000000-0000-0000-0000-000000000601', '00000000-0000-0000-0000-000000000701', 10000000);
    raise exception 'a horse entered foal trade twice' using errcode = 'XX000';
  exception
    when unique_violation then null;
  end;

  begin
    update public.horses
    set owner_id = '00000000-0000-0000-0000-000000000811'
    where id = '00000000-0000-0000-0000-000000000701';
    raise exception 'listed foal accepted a normal Owner assignment' using errcode = 'XX000';
  exception
    when check_violation then null;
  end;
end;
$$;

-- PLAYER A submits their private inquiry and first bid.
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000901', true);
select set_config('request.jwt.claim.role', 'authenticated', true);

select public.create_foal_trade_inquiry('00000000-0000-0000-0000-000000000501');

-- A same-Lot inquiry retry returns the original row rather than consuming a
-- second inquiry or surfacing the unique constraint as a client failure.
do $$
declare
  first_inquiry_id uuid;
  retried_inquiry_id uuid;
begin
  select id into first_inquiry_id
  from public.foal_trade_inquiries
  where session_id = '00000000-0000-0000-0000-000000000601'
    and owner_id = '00000000-0000-0000-0000-000000000811';

  select id into retried_inquiry_id
  from public.create_foal_trade_inquiry('00000000-0000-0000-0000-000000000501');

  if retried_inquiry_id <> first_inquiry_id then
    raise exception 'same-Lot inquiry retry did not return the original inquiry';
  end if;
end;
$$;

select public.submit_foal_trade_secret_bid('00000000-0000-0000-0000-000000000501', 20000000);

-- A same-amount submission is a no-op: it must preserve priority and history.
do $$
declare
  first_priority_at timestamptz;
  retried_priority_at timestamptz;
  bid_history_count integer;
begin
  select priority_at into first_priority_at
  from public.secret_bid_offers
  where lot_id = '00000000-0000-0000-0000-000000000501'
    and owner_id = '00000000-0000-0000-0000-000000000811';

  perform pg_sleep(0.01);
  select priority_at into retried_priority_at
  from public.submit_foal_trade_secret_bid('00000000-0000-0000-0000-000000000501', 20000000);

  select count(*) into bid_history_count
  from public.secret_bid_offer_history
  where lot_id = '00000000-0000-0000-0000-000000000501'
    and owner_id = '00000000-0000-0000-0000-000000000811';

  if retried_priority_at <> first_priority_at or bid_history_count <> 1 then
    raise exception 'same-amount secret-bid retry refreshed priority or wrote history';
  end if;
end;
$$;

-- PLAYER keeps access to the three Player RPCs above, but cannot invoke the
-- internal settlement function or complete a GM-only settlement wrapper.
do $$
begin
  begin
    perform public.settle_foal_trade_lot_internal(
      '00000000-0000-0000-0000-000000000501',
      null,
      null,
      null
    );
    raise exception 'PLAYER directly invoked internal settlement implementation' using errcode = 'XX000';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform public.settle_foal_trade_lot(
      '00000000-0000-0000-0000-000000000501',
      'PLAYER must not settle'
    );
    raise exception 'PLAYER completed a GM settlement RPC' using errcode = 'XX000';
  exception
    when insufficient_privilege then null;
  end;
end;
$$;

reset role;

-- GM can see every private record and answer the inquiry.
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000903', true);
select set_config('request.jwt.claim.role', 'authenticated', true);

do $$
declare
  inquiry_count integer;
  bid_count integer;
begin
  select count(*) into inquiry_count from public.foal_trade_inquiries;
  select count(*) into bid_count from public.secret_bid_offers;

  if inquiry_count <> 1 or bid_count <> 1 then
    raise exception 'GM could not inspect all current private foal-trade records';
  end if;
end;
$$;

update public.foal_trade_inquiries
set gm_comment = 'GM private assessment for Owner A'
where owner_id = '00000000-0000-0000-0000-000000000811';

reset role;

-- PLAYER B must not learn whether A used either private action.
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000902', true);
select set_config('request.jwt.claim.role', 'authenticated', true);

do $$
declare
  visible_inquiries integer;
  visible_bids integer;
  visible_bid_history integer;
begin
  select count(*) into visible_inquiries from public.foal_trade_inquiries;
  select count(*) into visible_bids from public.secret_bid_offers;
  select count(*) into visible_bid_history from public.secret_bid_offer_history;

  if visible_inquiries <> 0 or visible_bids <> 0 or visible_bid_history <> 0 then
    raise exception 'PLAYER B could infer PLAYER A private foal-trade activity';
  end if;
end;
$$;

reset role;

-- PLAYER A can see their own inquiry and GM response, but may ask only once.
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000901', true);
select set_config('request.jwt.claim.role', 'authenticated', true);

do $$
declare
  visible_comment text;
  inquiry_status public.foal_trade_inquiry_status;
begin
  select gm_comment, status
  into visible_comment, inquiry_status
  from public.foal_trade_inquiries;

  if visible_comment <> 'GM private assessment for Owner A'
    or inquiry_status <> 'ANSWERED'::public.foal_trade_inquiry_status then
    raise exception 'PLAYER A could not read their GM inquiry response';
  end if;

  begin
    perform public.create_foal_trade_inquiry('00000000-0000-0000-0000-000000000502');
    raise exception 'PLAYER A submitted a second inquiry in one session' using errcode = 'XX000';
  exception
    when unique_violation then null;
  end;
end;
$$;

-- A freezes 20m + 20m. A failed third 15m bid proves that funds are checked
-- in the RPC transaction, rather than trusting an application-side balance.
select public.submit_foal_trade_secret_bid('00000000-0000-0000-0000-000000000502', 20000000);

do $$
declare
  initial_priority_at timestamptz;
  increased_priority_at timestamptz;
  returned_priority_at timestamptz;
  active_frozen bigint;
begin
  select priority_at
  into initial_priority_at
  from public.secret_bid_offers
  where lot_id = '00000000-0000-0000-0000-000000000501';

  perform pg_sleep(0.01);
  perform public.submit_foal_trade_secret_bid('00000000-0000-0000-0000-000000000501', 25000000);
  select priority_at
  into increased_priority_at
  from public.secret_bid_offers
  where lot_id = '00000000-0000-0000-0000-000000000501';

  perform pg_sleep(0.01);
  perform public.submit_foal_trade_secret_bid('00000000-0000-0000-0000-000000000501', 20000000);

  select priority_at
  into returned_priority_at
  from public.secret_bid_offers
  where lot_id = '00000000-0000-0000-0000-000000000501';

  if increased_priority_at <= initial_priority_at
    or returned_priority_at <= increased_priority_at then
    raise exception 'a genuine secret-bid amount change did not receive a new priority_at';
  end if;

  begin
    perform public.submit_foal_trade_secret_bid('00000000-0000-0000-0000-000000000503', 15000000);
    raise exception 'PLAYER A over-froze funds with a third bid' using errcode = 'XX000';
  exception
    when sqlstate 'P0001' then null;
  end;

  perform public.submit_foal_trade_secret_bid('00000000-0000-0000-0000-000000000501', 10000000);
  perform public.submit_foal_trade_secret_bid('00000000-0000-0000-0000-000000000503', 15000000);

  select coalesce(sum(amount), 0)
  into active_frozen
  from public.secret_bid_offers
  where owner_id = '00000000-0000-0000-0000-000000000811'
    and status = 'ACTIVE'::public.secret_bid_offer_status;

  if active_frozen <> 45000000 then
    raise exception 'expected 45m frozen after A reduced Horse 1 and bid Horse 3, got %', active_frozen;
  end if;
end;
$$;

-- Release the temporary funding-test bids, then create the equal-price winner
-- case on Horse 4. A's bid is intentionally earlier than B's.
do $$
declare
  withdrawn_priority_at timestamptz;
  reactivated_priority_at timestamptz;
  first_withdraw_history_count integer;
  retried_withdraw_history_count integer;
  reactivated_history_count integer;
begin
  perform public.withdraw_foal_trade_secret_bid('00000000-0000-0000-0000-000000000502');
  select count(*) into first_withdraw_history_count
  from public.secret_bid_offer_history
  where lot_id = '00000000-0000-0000-0000-000000000502'
    and owner_id = '00000000-0000-0000-0000-000000000811'
    and event_type = 'WITHDRAWN'::public.secret_bid_offer_history_event;

  perform public.withdraw_foal_trade_secret_bid('00000000-0000-0000-0000-000000000502');
  select count(*) into retried_withdraw_history_count
  from public.secret_bid_offer_history
  where lot_id = '00000000-0000-0000-0000-000000000502'
    and owner_id = '00000000-0000-0000-0000-000000000811'
    and event_type = 'WITHDRAWN'::public.secret_bid_offer_history_event;

  select priority_at into withdrawn_priority_at
  from public.secret_bid_offers
  where lot_id = '00000000-0000-0000-0000-000000000502'
    and owner_id = '00000000-0000-0000-0000-000000000811';

  perform pg_sleep(0.01);
  perform public.submit_foal_trade_secret_bid('00000000-0000-0000-0000-000000000502', 20000000);
  select priority_at into reactivated_priority_at
  from public.secret_bid_offers
  where lot_id = '00000000-0000-0000-0000-000000000502'
    and owner_id = '00000000-0000-0000-0000-000000000811';
  select count(*) into reactivated_history_count
  from public.secret_bid_offer_history
  where lot_id = '00000000-0000-0000-0000-000000000502'
    and owner_id = '00000000-0000-0000-0000-000000000811'
    and event_type = 'REACTIVATED'::public.secret_bid_offer_history_event;

  if first_withdraw_history_count <> 1
    or retried_withdraw_history_count <> 1
    or reactivated_history_count <> 1
    or reactivated_priority_at <= withdrawn_priority_at then
    raise exception 'withdrawal retry or reactivation did not preserve bid idempotency semantics';
  end if;

  perform public.withdraw_foal_trade_secret_bid('00000000-0000-0000-0000-000000000502');
end;
$$;
select public.withdraw_foal_trade_secret_bid('00000000-0000-0000-0000-000000000503');
select public.submit_foal_trade_secret_bid('00000000-0000-0000-0000-000000000504', 20000000);

do $$
begin
  begin
    insert into public.secret_bid_offers (session_id, lot_id, owner_id, amount)
    values (
      '00000000-0000-0000-0000-000000000601',
      '00000000-0000-0000-0000-000000000505',
      '00000000-0000-0000-0000-000000000811',
      10000000
    );
    raise exception 'PLAYER directly inserted a secret bid' using errcode = 'XX000';
  exception
    when insufficient_privilege then null;
  end;
end;
$$;

reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000902', true);
select set_config('request.jwt.claim.role', 'authenticated', true);

select pg_sleep(0.01);
select public.submit_foal_trade_secret_bid('00000000-0000-0000-0000-000000000504', 20000000);

do $$
declare
  own_bid_count integer;
  a_bid_count integer;
  inquiry_count integer;
begin
  select count(*) into own_bid_count from public.secret_bid_offers;
  select count(*) into a_bid_count
  from public.secret_bid_offers
  where owner_id = '00000000-0000-0000-0000-000000000811';
  select count(*) into inquiry_count from public.foal_trade_inquiries;

  if own_bid_count <> 1 or a_bid_count <> 0 or inquiry_count <> 0 then
    raise exception 'PLAYER B could query PLAYER A secret bids or inquiry usage';
  end if;
end;
$$;

reset role;

-- Move the server-side deadline into the past. PLAYER writes must now fail even
-- though the session status has intentionally not been manually changed.
update public.foal_trade_sessions
set ends_at = clock_timestamp() - interval '1 second'
where id = '00000000-0000-0000-0000-000000000601';

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000901', true);
select set_config('request.jwt.claim.role', 'authenticated', true);

do $$
begin
  begin
    perform public.submit_foal_trade_secret_bid('00000000-0000-0000-0000-000000000501', 11000000);
    raise exception 'PLAYER modified a secret bid after the deadline' using errcode = 'XX000';
  exception
    when sqlstate 'P0001' then null;
  end;

  begin
    perform public.withdraw_foal_trade_secret_bid('00000000-0000-0000-0000-000000000504');
    raise exception 'PLAYER withdrew a secret bid after the deadline' using errcode = 'XX000';
  exception
    when sqlstate 'P0001' then null;
  end;
end;
$$;

reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000902', true);
select set_config('request.jwt.claim.role', 'authenticated', true);

do $$
begin
  begin
    perform public.submit_foal_trade_secret_bid('00000000-0000-0000-0000-000000000501', 10000000);
    raise exception 'PLAYER created a new secret bid after the deadline' using errcode = 'XX000';
  exception
    when sqlstate 'P0001' then null;
  end;

  begin
    perform public.create_foal_trade_inquiry('00000000-0000-0000-0000-000000000502');
    raise exception 'PLAYER created an inquiry after the deadline' using errcode = 'XX000';
  exception
    when sqlstate 'P0001' then null;
  end;
end;
$$;

reset role;

-- GM settlement picks the equal-price earlier A offer, is idempotent, debits
-- exactly once, marks the Horse owned, and releases both Lot 4 bid freezes.
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000903', true);
select set_config('request.jwt.claim.role', 'authenticated', true);

select public.settle_foal_trade_lot('00000000-0000-0000-0000-000000000504', 'local test equal-price winner');
select public.settle_foal_trade_lot('00000000-0000-0000-0000-000000000504', 'duplicate must be idempotent');
select public.settle_foal_trade_lot('00000000-0000-0000-0000-000000000505', 'local test unsold lot');

do $$
declare
  settlement_count integer;
  transaction_count integer;
  audit_count integer;
  active_lot_four_count integer;
  visible_secret_bids integer;
  session_status public.foal_trade_session_status;
begin
  select count(*)
  into settlement_count
  from public.foal_trade_settlements
  where lot_id = '00000000-0000-0000-0000-000000000504';

  select count(*)
  into transaction_count
  from public.financial_transactions
  where source_entity_type = 'FOAL_TRADE_SETTLEMENT';

  select count(*)
  into audit_count
  from public.audit_logs
  where action = 'FOAL_TRADE_LOT_SETTLED_SOLD'
    and entity_id = '00000000-0000-0000-0000-000000000504';

  select count(*)
  into active_lot_four_count
  from public.secret_bid_offers
  where lot_id = '00000000-0000-0000-0000-000000000504'
    and status = 'ACTIVE'::public.secret_bid_offer_status;

  select count(*) into visible_secret_bids from public.secret_bid_offers;
  select status into session_status
  from public.foal_trade_sessions
  where id = '00000000-0000-0000-0000-000000000601';

  if settlement_count <> 1
    or transaction_count <> 1
    or audit_count <> 1
    or active_lot_four_count <> 0
    or visible_secret_bids <> 5
    or session_status <> 'OPEN'::public.foal_trade_session_status then
    raise exception 'GM settlement was not idempotent or GM could not read all bids';
  end if;

  if not exists (
    select 1
    from public.foal_trade_settlements
    where lot_id = '00000000-0000-0000-0000-000000000504'
      and status = 'SOLD'::public.foal_trade_settlement_status
      and recommended_offer_id = winning_offer_id
      and not is_override
      and override_reason is null
      and winner_owner_id = '00000000-0000-0000-0000-000000000811'
      and amount = 20000000
  ) then
    raise exception 'earlier equal-price bid did not win settlement';
  end if;

  if not exists (
    select 1
    from public.financial_transactions
    where owner_id = '00000000-0000-0000-0000-000000000811'
      and amount = -20000000
      and transaction_kind = 'FOAL_TRADE_PURCHASE'
      and source_entity_type = 'FOAL_TRADE_SETTLEMENT'
  ) then
    raise exception 'winning Owner was not debited exactly once';
  end if;

  if not exists (
    select 1
    from public.horses
    where id = '00000000-0000-0000-0000-000000000704'
      and owner_id = '00000000-0000-0000-0000-000000000811'
      and life_stage = 'OWNED_FOAL'::public.horse_life_stage
  ) then
    raise exception 'winning Horse assignment or life stage is incorrect';
  end if;

  if not exists (
    select 1
    from public.foal_trade_lots
    where id = '00000000-0000-0000-0000-000000000505'
      and status = 'UNSOLD'::public.foal_trade_lot_status
  ) or not exists (
    select 1
    from public.horses
    where id = '00000000-0000-0000-0000-000000000705'
      and owner_id is null
      and life_stage = 'FOAL'::public.horse_life_stage
  ) then
    raise exception 'unsold foal did not remain unowned FOAL';
  end if;
end;
$$;

reset role;

-- Even after settlement, PLAYER B sees only their own lost bid and cannot read
-- the GM-only settlement row or any other Owner's hidden history.
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000902', true);
select set_config('request.jwt.claim.role', 'authenticated', true);

do $$
declare
  visible_bids integer;
  visible_history integer;
  visible_settlements integer;
  visible_public_winner uuid;
  visible_public_amount bigint;
  visible_a_bids integer;
begin
  select count(*) into visible_bids from public.secret_bid_offers;
  select count(*) into visible_history from public.secret_bid_offer_history;
  select count(*) into visible_settlements from public.foal_trade_settlements;
  select winner_owner_id, amount
  into visible_public_winner, visible_public_amount
  from public.foal_trade_public_settlements
  where lot_id = '00000000-0000-0000-0000-000000000504';
  select count(*) into visible_a_bids
  from public.secret_bid_offers
  where owner_id = '00000000-0000-0000-0000-000000000811';

  if visible_bids <> 1
    or visible_history <> 2
    or visible_settlements <> 0
    or visible_a_bids <> 0
    or visible_public_winner <> '00000000-0000-0000-0000-000000000811'
    or visible_public_amount <> 20000000 then
    raise exception 'PLAYER B gained post-settlement visibility into private trade data';
  end if;
end;
$$;

reset role;

-- Both PLAYER A and PLAYER B may read the narrowly scoped public outcome, but
-- PLAYER A still cannot inspect PLAYER B's failed offer after settlement.
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000901', true);
select set_config('request.jwt.claim.role', 'authenticated', true);

do $$
declare
  visible_public_winner uuid;
  visible_public_amount bigint;
  visible_b_bids integer;
begin
  select winner_owner_id, amount
  into visible_public_winner, visible_public_amount
  from public.foal_trade_public_settlements
  where lot_id = '00000000-0000-0000-0000-000000000504';
  select count(*) into visible_b_bids
  from public.secret_bid_offers
  where owner_id = '00000000-0000-0000-0000-000000000812';

  if visible_public_winner <> '00000000-0000-0000-0000-000000000811'
    or visible_public_amount <> 20000000
    or visible_b_bids <> 0 then
    raise exception 'PLAYER A did not receive only the safe public settlement outcome';
  end if;
end;
$$;

reset role;

-- A separate 2027 lot verifies the explicit GM override path. B has the
-- higher system-recommended bid; GM must provide a reason to select A instead.
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
  '00000000-0000-0000-0000-000000000707',
  27001,
  2027,
  'Foal Trade Override Horse',
  'FEMALE',
  'BAY',
  'Override Sire',
  'Override Line',
  'Override Broodmare Sire'
);

insert into public.foal_trade_sessions (id, wp_year, starts_at, ends_at, status)
values (
  '00000000-0000-0000-0000-000000000602',
  2027,
  clock_timestamp() - interval '1 hour',
  clock_timestamp() + interval '1 hour',
  'OPEN'
);

insert into public.foal_trade_lots (id, session_id, horse_id, minimum_price)
values (
  '00000000-0000-0000-0000-000000000506',
  '00000000-0000-0000-0000-000000000602',
  '00000000-0000-0000-0000-000000000707',
  10000000
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000901', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select public.submit_foal_trade_secret_bid('00000000-0000-0000-0000-000000000506', 20000000);
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000902', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select public.submit_foal_trade_secret_bid('00000000-0000-0000-0000-000000000506', 25000000);
reset role;

update public.foal_trade_sessions
set ends_at = clock_timestamp() - interval '1 second'
where id = '00000000-0000-0000-0000-000000000602';

-- PLAYER B cannot invoke the exceptional GM-only RPC, even when selecting
-- their own valid bid.
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000902', true);
select set_config('request.jwt.claim.role', 'authenticated', true);

do $$
begin
  begin
    perform public.settle_foal_trade_lot_override(
      '00000000-0000-0000-0000-000000000506',
      (
        select id
        from public.secret_bid_offers
        where lot_id = '00000000-0000-0000-0000-000000000506'
          and owner_id = '00000000-0000-0000-0000-000000000812'
      ),
      'PLAYER must not be able to override'
    );
    raise exception 'PLAYER invoked the GM override RPC' using errcode = 'XX000';
  exception
    when insufficient_privilege then null;
  end;
end;
$$;

reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000903', true);
select set_config('request.jwt.claim.role', 'authenticated', true);

do $$
begin
  begin
    perform public.settle_foal_trade_lot_override(
      '00000000-0000-0000-0000-000000000506',
      (
        select id
        from public.secret_bid_offers
        where lot_id = '00000000-0000-0000-0000-000000000506'
          and owner_id = '00000000-0000-0000-0000-000000000811'
      ),
      ' '
    );
    raise exception 'GM override accepted an empty reason' using errcode = 'XX000';
  exception
    when check_violation then null;
  end;
end;
$$;

select public.settle_foal_trade_lot_override(
  '00000000-0000-0000-0000-000000000506',
  (
    select id
    from public.secret_bid_offers
    where lot_id = '00000000-0000-0000-0000-000000000506'
      and owner_id = '00000000-0000-0000-0000-000000000811'
  ),
  'GM exceptional assessment requires Owner A selection'
);
select public.settle_foal_trade_lot_override(
  '00000000-0000-0000-0000-000000000506',
  (
    select id
    from public.secret_bid_offers
    where lot_id = '00000000-0000-0000-0000-000000000506'
      and owner_id = '00000000-0000-0000-0000-000000000811'
  ),
  'duplicate override must be idempotent'
);

do $$
declare
  v_recommended_offer_id uuid;
  v_selected_offer_id uuid;
  v_settlement_id uuid;
  v_settlement_count integer;
  v_transaction_count integer;
  v_audit_count integer;
begin
  select recommended_offer_id, winning_offer_id, id
  into v_recommended_offer_id, v_selected_offer_id, v_settlement_id
  from public.foal_trade_settlements
  where lot_id = '00000000-0000-0000-0000-000000000506';

  select count(*) into v_settlement_count
  from public.foal_trade_settlements
  where lot_id = '00000000-0000-0000-0000-000000000506';
  select count(*) into v_transaction_count
  from public.financial_transactions
  where source_entity_type = 'FOAL_TRADE_SETTLEMENT'
    and source_entity_id = v_settlement_id;
  select count(*) into v_audit_count
  from public.audit_logs
  where action = 'FOAL_TRADE_LOT_SETTLED_OVERRIDE'
    and entity_id = '00000000-0000-0000-0000-000000000506'
    and after_data ->> 'recommended_offer_id' = v_recommended_offer_id::text
    and after_data ->> 'selected_offer_id' = v_selected_offer_id::text;

  if v_settlement_count <> 1
    or v_transaction_count <> 1
    or v_audit_count <> 1
    or v_recommended_offer_id <> (
      select id
      from public.secret_bid_offers
      where lot_id = '00000000-0000-0000-0000-000000000506'
        and owner_id = '00000000-0000-0000-0000-000000000812'
    )
    or v_selected_offer_id <> (
      select id
      from public.secret_bid_offers
      where lot_id = '00000000-0000-0000-0000-000000000506'
        and owner_id = '00000000-0000-0000-0000-000000000811'
    )
    or not exists (
      select 1
      from public.foal_trade_settlements
      where id = v_settlement_id
        and is_override
        and override_reason = 'GM exceptional assessment requires Owner A selection'
        and winner_owner_id = '00000000-0000-0000-0000-000000000811'
        and amount = 20000000
    )
    or not exists (
      select 1
      from public.horses
      where id = '00000000-0000-0000-0000-000000000707'
        and owner_id = '00000000-0000-0000-0000-000000000811'
        and life_stage = 'OWNED_FOAL'::public.horse_life_stage
    ) then
    raise exception 'GM override did not preserve recommendation, audit, or idempotent settlement effects';
  end if;
end;
$$;

reset role;

-- The safe public settlement projection is visible to both Owners, while each
-- PLAYER remains unable to inspect the other Owner's failed bid or history.
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000901', true);
select set_config('request.jwt.claim.role', 'authenticated', true);

do $$
declare
  visible_owner uuid;
  visible_amount bigint;
  visible_b_bids integer;
begin
  select winner_owner_id, amount
  into visible_owner, visible_amount
  from public.foal_trade_public_settlements
  where lot_id = '00000000-0000-0000-0000-000000000506';
  select count(*) into visible_b_bids
  from public.secret_bid_offers
  where lot_id = '00000000-0000-0000-0000-000000000506'
    and owner_id = '00000000-0000-0000-0000-000000000812';

  if visible_owner <> '00000000-0000-0000-0000-000000000811'
    or visible_amount <> 20000000
    or visible_b_bids <> 0 then
    raise exception 'PLAYER A did not receive only the public override outcome';
  end if;
end;
$$;

reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000902', true);
select set_config('request.jwt.claim.role', 'authenticated', true);

do $$
declare
  visible_owner uuid;
  visible_amount bigint;
  visible_a_bids integer;
begin
  select winner_owner_id, amount
  into visible_owner, visible_amount
  from public.foal_trade_public_settlements
  where lot_id = '00000000-0000-0000-0000-000000000506';
  select count(*) into visible_a_bids
  from public.secret_bid_offers
  where lot_id = '00000000-0000-0000-0000-000000000506'
    and owner_id = '00000000-0000-0000-0000-000000000811';

  if visible_owner <> '00000000-0000-0000-0000-000000000811'
    or visible_amount <> 20000000
    or visible_a_bids <> 0 then
    raise exception 'PLAYER B could infer another Owner failed or winning bid details';
  end if;
end;
$$;

reset role;

-- A post-bid formal GM correction can lower an Owner's account funds. The
-- subsequent settlement must re-check the selected bid plus every other ACTIVE
-- freeze and leave all business facts unchanged when the check fails.
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
  ('00000000-0000-0000-0000-000000000708', 28001, 2028, 'Funding Check Horse A', 'MALE', 'BAY', 'Funding Sire A', 'Funding Line A', 'Funding Broodmare A'),
  ('00000000-0000-0000-0000-000000000709', 28002, 2028, 'Funding Check Horse B', 'FEMALE', 'CHESTNUT', 'Funding Sire B', 'Funding Line B', 'Funding Broodmare B');

insert into public.foal_trade_sessions (id, wp_year, starts_at, ends_at, status)
values (
  '00000000-0000-0000-0000-000000000603',
  2028,
  clock_timestamp() - interval '1 hour',
  clock_timestamp() + interval '1 hour',
  'OPEN'
);

insert into public.foal_trade_lots (id, session_id, horse_id, minimum_price)
values
  ('00000000-0000-0000-0000-000000000507', '00000000-0000-0000-0000-000000000603', '00000000-0000-0000-0000-000000000708', 0),
  ('00000000-0000-0000-0000-000000000508', '00000000-0000-0000-0000-000000000603', '00000000-0000-0000-0000-000000000709', 0);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000904', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select public.submit_foal_trade_secret_bid('00000000-0000-0000-0000-000000000507', 30000000);
select public.submit_foal_trade_secret_bid('00000000-0000-0000-0000-000000000508', 20000000);
reset role;

-- This root-level fixture represents the controlled server-side GM correction;
-- ordinary authenticated clients retain no direct ledger write privilege.
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
  '00000000-0000-0000-0000-000000000813',
  -10000000,
  'GM_CORRECTION',
  'LOCAL_TEST_CORRECTION',
  '00000000-0000-0000-0000-000000000603',
  '00000000-0000-0000-0000-000000000903',
  'Local test post-bid correction'
);

update public.foal_trade_sessions
set ends_at = clock_timestamp() - interval '1 second'
where id = '00000000-0000-0000-0000-000000000603';

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000903', true);
select set_config('request.jwt.claim.role', 'authenticated', true);

do $$
begin
  begin
    perform public.settle_foal_trade_lot('00000000-0000-0000-0000-000000000507', 'must fail after correction');
    raise exception 'settlement ignored selected Owner other active bid freezes' using errcode = 'XX000';
  exception
    when sqlstate 'P0001' then null;
  end;
end;
$$;

reset role;

do $$
begin
  if exists (
    select 1
    from public.foal_trade_settlements
    where lot_id = '00000000-0000-0000-0000-000000000507'
  ) or exists (
    select 1
    from public.financial_transactions
    where owner_id = '00000000-0000-0000-0000-000000000813'
      and transaction_kind = 'FOAL_TRADE_PURCHASE'
  ) or exists (
    select 1
    from public.horses
    where id = '00000000-0000-0000-0000-000000000708'
      and owner_id is not null
  ) or not exists (
    select 1
    from public.foal_trade_lots
    where id = '00000000-0000-0000-0000-000000000507'
      and status = 'LISTED'::public.foal_trade_lot_status
  ) then
    raise exception 'failed funding-check settlement left a transactional side effect';
  end if;
end;
$$;

-- Only an ended OPEN session, CLOSED session, or REVIEWING session may settle.
-- DRAFT must fail without recording an UNSOLD result.
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
  ('00000000-0000-0000-0000-000000000710', 29001, 2029, 'Draft Status Horse', 'MALE', 'BAY', 'Draft Sire', 'Draft Line', 'Draft Broodmare'),
  ('00000000-0000-0000-0000-000000000711', 30001, 2030, 'Closed Status Horse', 'FEMALE', 'BROWN', 'Closed Sire', 'Closed Line', 'Closed Broodmare'),
  ('00000000-0000-0000-0000-000000000712', 31001, 2031, 'Reviewing Status Horse', 'MALE', 'GREY', 'Reviewing Sire', 'Reviewing Line', 'Reviewing Broodmare');

insert into public.foal_trade_sessions (id, wp_year, starts_at, ends_at, status)
values
  ('00000000-0000-0000-0000-000000000604', 2029, clock_timestamp() - interval '2 hours', clock_timestamp() - interval '1 hour', 'DRAFT'),
  ('00000000-0000-0000-0000-000000000605', 2030, clock_timestamp() - interval '1 hour', clock_timestamp() + interval '1 hour', 'OPEN'),
  ('00000000-0000-0000-0000-000000000606', 2031, clock_timestamp() - interval '1 hour', clock_timestamp() + interval '1 hour', 'OPEN');

insert into public.foal_trade_lots (id, session_id, horse_id, minimum_price)
values
  ('00000000-0000-0000-0000-000000000509', '00000000-0000-0000-0000-000000000604', '00000000-0000-0000-0000-000000000710', 0),
  ('00000000-0000-0000-0000-000000000510', '00000000-0000-0000-0000-000000000605', '00000000-0000-0000-0000-000000000711', 0),
  ('00000000-0000-0000-0000-000000000511', '00000000-0000-0000-0000-000000000606', '00000000-0000-0000-0000-000000000712', 0);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000902', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select public.submit_foal_trade_secret_bid('00000000-0000-0000-0000-000000000510', 10000000);
select public.submit_foal_trade_secret_bid('00000000-0000-0000-0000-000000000511', 10000000);
reset role;

update public.foal_trade_sessions
set ends_at = clock_timestamp() - interval '1 second',
    status = case
      when id = '00000000-0000-0000-0000-000000000605' then 'CLOSED'::public.foal_trade_session_status
      else 'REVIEWING'::public.foal_trade_session_status
    end
where id in (
  '00000000-0000-0000-0000-000000000605',
  '00000000-0000-0000-0000-000000000606'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000903', true);
select set_config('request.jwt.claim.role', 'authenticated', true);

do $$
begin
  begin
    perform public.settle_foal_trade_lot('00000000-0000-0000-0000-000000000509', 'DRAFT must not settle');
    raise exception 'DRAFT session was accepted for settlement' using errcode = 'XX000';
  exception
    when sqlstate 'P0001' then null;
  end;
end;
$$;

select public.settle_foal_trade_lot('00000000-0000-0000-0000-000000000510', 'CLOSED session may settle');
select public.settle_foal_trade_lot('00000000-0000-0000-0000-000000000511', 'REVIEWING session may settle');

reset role;

do $$
begin
  if exists (
    select 1
    from public.foal_trade_settlements
    where lot_id = '00000000-0000-0000-0000-000000000509'
  ) or (
    select count(*)
    from public.foal_trade_settlements
    where lot_id in (
      '00000000-0000-0000-0000-000000000510',
      '00000000-0000-0000-0000-000000000511'
    )
      and status = 'SOLD'::public.foal_trade_settlement_status
  ) <> 2 or (
    select count(*)
    from public.foal_trade_settlements
    where lot_id in (
      '00000000-0000-0000-0000-000000000510',
      '00000000-0000-0000-0000-000000000511'
    )
  ) <> 2 then
    raise exception 'session-status settlement rules are incorrect';
  end if;
end;
$$;

rollback;
