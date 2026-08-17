-- Local-only verification for the v0.3 public-auction migration.
-- Run only after `npx supabase db reset`; all fixtures are rolled back.

begin;

-- Structural and ACL baseline. New public-auction data is never anonymous,
-- and only the explicit RPC surface is callable by authenticated clients.
do $$
begin
  if not exists (
    select 1
    from pg_proc as procedure
    where procedure.oid = 'public.submit_public_auction_bid(uuid,uuid,bigint,uuid)'::regprocedure
  ) or not exists (
    select 1
    from pg_proc as procedure
    where procedure.oid = 'public.get_current_owner_financial_summary()'::regprocedure
  ) or not exists (
    select 1
    from pg_proc as procedure
    where procedure.oid = 'public.reveal_public_auction_lot(uuid)'::regprocedure
  ) then
    raise exception 'public-auction RPCs do not exist';
  end if;

  if not has_function_privilege('authenticated', 'public.submit_public_auction_bid(uuid,uuid,bigint,uuid)'::regprocedure, 'EXECUTE')
    or has_function_privilege('anon', 'public.submit_public_auction_bid(uuid,uuid,bigint,uuid)'::regprocedure, 'EXECUTE')
    or has_function_privilege('service_role', 'public.submit_public_auction_bid(uuid,uuid,bigint,uuid)'::regprocedure, 'EXECUTE')
    or not has_function_privilege('authenticated', 'public.get_current_owner_financial_summary()'::regprocedure, 'EXECUTE')
    or has_function_privilege('anon', 'public.get_current_owner_financial_summary()'::regprocedure, 'EXECUTE')
    or has_function_privilege('service_role', 'public.get_current_owner_financial_summary()'::regprocedure, 'EXECUTE') then
    raise exception 'public-auction PLAYER RPC ACL is incorrect';
  end if;

  if not has_function_privilege('authenticated', 'public.reveal_public_auction_lot(uuid)'::regprocedure, 'EXECUTE')
    or has_function_privilege('anon', 'public.reveal_public_auction_lot(uuid)'::regprocedure, 'EXECUTE')
    or has_function_privilege('service_role', 'public.reveal_public_auction_lot(uuid)'::regprocedure, 'EXECUTE') then
    raise exception 'public-auction reveal RPC ACL is incorrect';
  end if;

  if has_function_privilege('authenticated', 'public.close_public_auction_round_if_elapsed(uuid)'::regprocedure, 'EXECUTE')
    or has_function_privilege('authenticated', 'public.enforce_public_auction_horse_lifecycle()'::regprocedure, 'EXECUTE') then
    raise exception 'public-auction internal helper has an authenticated EXECUTE grant';
  end if;

  if exists (
    select 1
    from pg_class as relation
    join pg_namespace as namespace on namespace.oid = relation.relnamespace
    where namespace.nspname = 'public'
      and relation.relname in (
        'public_auction_events', 'public_auction_lots', 'public_auction_rounds',
        'public_auction_lot_reviews', 'public_auction_bids',
        'public_auction_settlements', 'public_auction_rollback_requests'
      )
      and not relation.relrowsecurity
  ) then
    raise exception 'one or more public-auction tables do not enable RLS';
  end if;

  if has_table_privilege('anon', 'public.public_auction_events', 'SELECT')
    or has_table_privilege('anon', 'public.public_auction_public_settlements', 'SELECT')
    or not has_table_privilege('authenticated', 'public.public_auction_public_settlements', 'SELECT') then
    raise exception 'public-auction table/view ACL is incorrect';
  end if;
end;
$$;

set local role anon;
do $$
begin
  begin
    perform public.submit_public_auction_bid(
      '00000000-0000-0000-0000-000000003501',
      '00000000-0000-0000-0000-000000003502', 10000000,
      '00000000-0000-0000-0000-000000003901'
    );
    raise exception 'anon invoked a public-auction bid RPC' using errcode = 'XX000';
  exception when insufficient_privilege then null;
  end;

  begin
    perform 1 from public.public_auction_events;
    raise exception 'anon read public-auction data' using errcode = 'XX000';
  exception when insufficient_privilege then null;
  end;
end;
$$;
reset role;

set local role service_role;
do $$
begin
  begin
    perform public.get_current_owner_financial_summary();
    raise exception 'service_role invoked the PLAYER public-auction funds RPC' using errcode = 'XX000';
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
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000003201', 'authenticated', 'authenticated', 'auction-player-a@example.test', 'not-used', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000003202', 'authenticated', 'authenticated', 'auction-player-b@example.test', 'not-used', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000003203', 'authenticated', 'authenticated', 'auction-player-c@example.test', 'not-used', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000003204', 'authenticated', 'authenticated', 'auction-gm@example.test', 'not-used', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now());

insert into public.owners (id, display_name, initial_funds)
values
  ('00000000-0000-0000-0000-000000003101', 'Auction Owner A', 100000000),
  ('00000000-0000-0000-0000-000000003102', 'Auction Owner B', 100000000),
  ('00000000-0000-0000-0000-000000003103', 'Auction Owner C', 100000000);

insert into public.user_profiles (id, role, owner_id, display_name)
values
  ('00000000-0000-0000-0000-000000003201', 'PLAYER', '00000000-0000-0000-0000-000000003101', 'Auction Player A'),
  ('00000000-0000-0000-0000-000000003202', 'PLAYER', '00000000-0000-0000-0000-000000003102', 'Auction Player B'),
  ('00000000-0000-0000-0000-000000003203', 'PLAYER', '00000000-0000-0000-0000-000000003103', 'Auction Player C'),
  ('00000000-0000-0000-0000-000000003204', 'GM', null, 'Auction GM');

insert into public.horses (
  id, horse_number, birth_year, foal_name, sex, coat_color,
  sire_name, sire_line, broodmare_sire_name
)
values
  ('00000000-0000-0000-0000-000000003301', 50301, 2050, 'Auction Foal One', 'MALE', 'BAY', 'Sire 1', 'Line 1', 'Dam Sire 1'),
  ('00000000-0000-0000-0000-000000003302', 50302, 2050, 'Auction Foal Two', 'FEMALE', 'CHESTNUT', 'Sire 2', 'Line 2', 'Dam Sire 2'),
  ('00000000-0000-0000-0000-000000003303', 50303, 2050, 'Auction Foal Three', 'MALE', 'BROWN', 'Sire 3', 'Line 3', 'Dam Sire 3'),
  ('00000000-0000-0000-0000-000000003304', 50304, 2050, 'Auction Foal Four', 'FEMALE', 'GREY', 'Sire 4', 'Line 4', 'Dam Sire 4'),
  ('00000000-0000-0000-0000-000000003305', 50305, 2050, 'Auction Foal Five', 'MALE', 'BAY', 'Sire 5', 'Line 5', 'Dam Sire 5'),
  ('00000000-0000-0000-0000-000000003306', 50306, 2050, 'Auction Foal Six', 'FEMALE', 'CHESTNUT', 'Sire 6', 'Line 6', 'Dam Sire 6'),
  ('00000000-0000-0000-0000-000000003307', 50307, 2050, 'Secret Freeze Foal', 'MALE', 'BAY', 'Sire 7', 'Line 7', 'Dam Sire 7'),
  ('00000000-0000-0000-0000-000000003308', 51308, 2051, 'Passed Sequence Foal One', 'MALE', 'BAY', 'Sire 8', 'Line 8', 'Dam Sire 8'),
  ('00000000-0000-0000-0000-000000003309', 51309, 2051, 'Passed Sequence Foal Two', 'FEMALE', 'GREY', 'Sire 9', 'Line 9', 'Dam Sire 9');

-- Every auction horse has an UNSOLD same-year foal-trade result. Horse Seven
-- remains a listed foal-trade Lot solely to establish a concurrent secret
-- freeze for Owner A.
insert into public.foal_trade_sessions (id, wp_year, starts_at, ends_at, status)
values (
  '00000000-0000-0000-0000-000000003401', 2050,
  clock_timestamp() - interval '1 hour', clock_timestamp() + interval '1 hour', 'OPEN'
), (
  '00000000-0000-0000-0000-000000003402', 2051,
  clock_timestamp() - interval '1 hour', clock_timestamp() + interval '1 hour', 'OPEN'
);

insert into public.foal_trade_lots (id, session_id, horse_id, minimum_price, status)
values
  ('00000000-0000-0000-0000-000000003411', '00000000-0000-0000-0000-000000003401', '00000000-0000-0000-0000-000000003301', 0, 'UNSOLD'),
  ('00000000-0000-0000-0000-000000003412', '00000000-0000-0000-0000-000000003401', '00000000-0000-0000-0000-000000003302', 0, 'UNSOLD'),
  ('00000000-0000-0000-0000-000000003413', '00000000-0000-0000-0000-000000003401', '00000000-0000-0000-0000-000000003303', 0, 'UNSOLD'),
  ('00000000-0000-0000-0000-000000003414', '00000000-0000-0000-0000-000000003401', '00000000-0000-0000-0000-000000003304', 0, 'UNSOLD'),
  ('00000000-0000-0000-0000-000000003415', '00000000-0000-0000-0000-000000003401', '00000000-0000-0000-0000-000000003305', 0, 'UNSOLD'),
  ('00000000-0000-0000-0000-000000003416', '00000000-0000-0000-0000-000000003401', '00000000-0000-0000-0000-000000003306', 0, 'UNSOLD'),
  ('00000000-0000-0000-0000-000000003417', '00000000-0000-0000-0000-000000003401', '00000000-0000-0000-0000-000000003307', 0, 'LISTED'),
  ('00000000-0000-0000-0000-000000003418', '00000000-0000-0000-0000-000000003402', '00000000-0000-0000-0000-000000003308', 0, 'UNSOLD'),
  ('00000000-0000-0000-0000-000000003419', '00000000-0000-0000-0000-000000003402', '00000000-0000-0000-0000-000000003309', 0, 'UNSOLD');

insert into public.foal_trade_settlements (lot_id, session_id, horse_id, status)
values
  ('00000000-0000-0000-0000-000000003411', '00000000-0000-0000-0000-000000003401', '00000000-0000-0000-0000-000000003301', 'UNSOLD'),
  ('00000000-0000-0000-0000-000000003412', '00000000-0000-0000-0000-000000003401', '00000000-0000-0000-0000-000000003302', 'UNSOLD'),
  ('00000000-0000-0000-0000-000000003413', '00000000-0000-0000-0000-000000003401', '00000000-0000-0000-0000-000000003303', 'UNSOLD'),
  ('00000000-0000-0000-0000-000000003414', '00000000-0000-0000-0000-000000003401', '00000000-0000-0000-0000-000000003304', 'UNSOLD'),
  ('00000000-0000-0000-0000-000000003415', '00000000-0000-0000-0000-000000003401', '00000000-0000-0000-0000-000000003305', 'UNSOLD'),
  ('00000000-0000-0000-0000-000000003416', '00000000-0000-0000-0000-000000003401', '00000000-0000-0000-0000-000000003306', 'UNSOLD'),
  ('00000000-0000-0000-0000-000000003418', '00000000-0000-0000-0000-000000003402', '00000000-0000-0000-0000-000000003308', 'UNSOLD'),
  ('00000000-0000-0000-0000-000000003419', '00000000-0000-0000-0000-000000003402', '00000000-0000-0000-0000-000000003309', 'UNSOLD');

-- A retains a 10m secret-bid freeze throughout the first live public round.
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000003201', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select public.submit_foal_trade_secret_bid('00000000-0000-0000-0000-000000003417', 10000000);
reset role;

-- GM configures six lots and all five mandatory reviews while the event is a
-- DRAFT, then opens the Event for sequential live Lots.
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000003204', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select public.create_public_auction_event(2050, 'Local public auction', 100000);

select public.create_public_auction_lot(
  (select id from public.public_auction_events where wp_year = 2050),
  horse_id, lot_number, 10000000, 25000000
)
from (values
  ('00000000-0000-0000-0000-000000003301'::uuid, 1),
  ('00000000-0000-0000-0000-000000003302'::uuid, 2),
  ('00000000-0000-0000-0000-000000003303'::uuid, 3),
  ('00000000-0000-0000-0000-000000003304'::uuid, 4),
  ('00000000-0000-0000-0000-000000003305'::uuid, 5),
  ('00000000-0000-0000-0000-000000003306'::uuid, 6)
) as configured_lot(horse_id, lot_number);

select public.upsert_public_auction_lot_review(lot.id, slot::smallint, 5::smallint, 'Local review ' || slot::text)
from public.public_auction_lots as lot
cross join generate_series(1, 5) as slot
where lot.event_id = (select id from public.public_auction_events where wp_year = 2050);

-- While still unrevealed, a GM may correct a review through the normal
-- upsert path. The same content must become immutable after reveal.
select public.upsert_public_auction_lot_review(
  (select id from public.public_auction_lots where horse_id = '00000000-0000-0000-0000-000000003301'),
  1::smallint, 4::smallint, 'Local amended review 1'
);

select public.set_public_auction_event_status(
  (select id from public.public_auction_events where wp_year = 2050),
  'OPEN'::public.public_auction_event_status
);

-- Future Lots exist for GM configuration but are not a public auction surface
-- until the GM explicitly reveals each one. Keep known UUIDs so the PLAYER
-- checks prove RLS still rejects direct queries by a guessed identifier.
select set_config('test.public_auction_reveal_lot_id', (select id::text from public.public_auction_lots where horse_id = '00000000-0000-0000-0000-000000003301'), true);
select set_config('test.public_auction_reveal_round_id', (select current_round_id::text from public.public_auction_lots where horse_id = '00000000-0000-0000-0000-000000003301'), true);
select set_config('test.public_auction_hidden_lot_id', (select id::text from public.public_auction_lots where horse_id = '00000000-0000-0000-0000-000000003302'), true);
select set_config('test.public_auction_hidden_round_id', (select current_round_id::text from public.public_auction_lots where horse_id = '00000000-0000-0000-0000-000000003302'), true);
reset role;

-- This out-of-band row is a local-only RLS fixture. It has a valid Lot/Round
-- relationship but an unrevealed Lot, proving Bid policy cannot be bypassed
-- merely by knowing an internal round UUID.
insert into public.public_auction_bids (lot_id, round_id, owner_id, amount, request_id)
values (
  current_setting('test.public_auction_hidden_lot_id', true)::uuid,
  current_setting('test.public_auction_hidden_round_id', true)::uuid,
  '00000000-0000-0000-0000-000000003103',
  10000000,
  '00000000-0000-0000-0000-000000003911'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000003201', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
do $$
begin
  if exists (select 1 from public.public_auction_lots where id = current_setting('test.public_auction_reveal_lot_id', true)::uuid)
    or exists (select 1 from public.public_auction_lot_reviews where lot_id = current_setting('test.public_auction_reveal_lot_id', true)::uuid)
    or exists (select 1 from public.public_auction_rounds where id = current_setting('test.public_auction_reveal_round_id', true)::uuid)
    or exists (select 1 from public.public_auction_lots where id = current_setting('test.public_auction_hidden_lot_id', true)::uuid)
    or exists (select 1 from public.public_auction_lot_reviews where lot_id = current_setting('test.public_auction_hidden_lot_id', true)::uuid)
    or exists (select 1 from public.public_auction_rounds where id = current_setting('test.public_auction_hidden_round_id', true)::uuid)
    or exists (select 1 from public.public_auction_bids where round_id = current_setting('test.public_auction_hidden_round_id', true)::uuid) then
    raise exception 'PLAYER read unrevealed public-auction Lot data';
  end if;
end;
$$;
reset role;

-- GM reads all configured content. Revealing a Lot is idempotent, exposes its
-- Lot/Review/Round data, but keeps the Round QUEUED and all deadline columns
-- empty until the separate open action.
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000003204', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
do $$
begin
  if not exists (select 1 from public.public_auction_lots where id = current_setting('test.public_auction_hidden_lot_id', true)::uuid)
    or not exists (select 1 from public.public_auction_lot_reviews where lot_id = current_setting('test.public_auction_hidden_lot_id', true)::uuid)
    or not exists (select 1 from public.public_auction_rounds where id = current_setting('test.public_auction_hidden_round_id', true)::uuid)
    or not exists (select 1 from public.public_auction_bids where round_id = current_setting('test.public_auction_hidden_round_id', true)::uuid) then
    raise exception 'GM could not read unrevealed public-auction configuration';
  end if;
end;
$$;
do $$
begin
  begin
    perform public.reveal_public_auction_lot(
      current_setting('test.public_auction_hidden_lot_id', true)::uuid
    );
    raise exception 'a future queued Lot was revealed before Lot 001' using errcode = 'XX000';
  exception when check_violation then null; when raise_exception then
    if sqlerrm not like '%earlier public auction lots%' then raise; end if;
  end;
end;
$$;
select public.reveal_public_auction_lot(current_setting('test.public_auction_reveal_lot_id', true)::uuid);
do $$
declare v_revealed_at timestamptz; v_retried_at timestamptz;
begin
  select revealed_at into v_revealed_at
  from public.public_auction_lots
  where id = current_setting('test.public_auction_reveal_lot_id', true)::uuid;

  perform public.reveal_public_auction_lot(current_setting('test.public_auction_reveal_lot_id', true)::uuid);

  select lot.revealed_at into v_retried_at
  from public.public_auction_lots as lot
  where lot.id = current_setting('test.public_auction_reveal_lot_id', true)::uuid;

  if v_revealed_at is null
    or v_retried_at <> v_revealed_at
    or (select status from public.public_auction_lots where id = current_setting('test.public_auction_reveal_lot_id', true)::uuid) <> 'QUEUED'::public.public_auction_lot_status
    or (select status from public.public_auction_rounds where id = current_setting('test.public_auction_reveal_round_id', true)::uuid) <> 'QUEUED'::public.public_auction_round_status
    or (select close_at from public.public_auction_rounds where id = current_setting('test.public_auction_reveal_round_id', true)::uuid) is not null
    or (select no_bid_deadline from public.public_auction_rounds where id = current_setting('test.public_auction_reveal_round_id', true)::uuid) is not null
    or (select count(*) from public.audit_logs where action = 'PUBLIC_AUCTION_LOT_REVEALED' and entity_id = current_setting('test.public_auction_reveal_lot_id', true)) <> 1 then
    raise exception 'Lot reveal was not an idempotent display-only action';
  end if;
end;
$$;
do $$
declare v_stars smallint; v_comment text;
begin
  begin
    perform public.upsert_public_auction_lot_review(
      current_setting('test.public_auction_reveal_lot_id', true)::uuid,
      1::smallint,
      1::smallint,
      'This untracked edit must fail'
    );
    raise exception 'a revealed public-auction review was edited normally' using errcode = 'XX000';
  exception when check_violation then null; when raise_exception then
    if sqlerrm not like '%controlled correction flow%' then raise; end if;
  end;

  select stars, comment into v_stars, v_comment
  from public.public_auction_lot_reviews
  where lot_id = current_setting('test.public_auction_reveal_lot_id', true)::uuid
    and slot = 1;

  if (v_stars, v_comment) <> (4::smallint, 'Local amended review 1') then
    raise exception 'a revealed public-auction review changed despite the freeze';
  end if;

  if (select count(*) from public.public_auction_lots
      where event_id = (select id from public.public_auction_events where wp_year = 2050)
        and revealed_at is not null
        and status not in ('SOLD'::public.public_auction_lot_status, 'PASSED'::public.public_auction_lot_status)) <> 1 then
    raise exception 'more than one revealed unfinished Lot exists after the first reveal';
  end if;
end;
$$;
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000003201', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
do $$
begin
  if not exists (
    select 1 from public.public_auction_lots
    where id = current_setting('test.public_auction_reveal_lot_id', true)::uuid
      and starting_price = 10000000
      and evaluation_value = 25000000
  )
    or not exists (select 1 from public.public_auction_lot_reviews where lot_id = current_setting('test.public_auction_reveal_lot_id', true)::uuid)
    or not exists (select 1 from public.public_auction_rounds where id = current_setting('test.public_auction_reveal_round_id', true)::uuid) then
    raise exception 'PLAYER could not read a revealed public-auction Lot';
  end if;
end;
$$;
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000003204', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select public.open_public_auction_lot(
  current_setting('test.public_auction_reveal_lot_id', true)::uuid
);
do $$
begin
  begin
    perform public.reveal_public_auction_lot(
      (select id from public.public_auction_lots where horse_id = '00000000-0000-0000-0000-000000003302')
    );
    raise exception 'a future Lot was revealed while Lot 001 was unfinished' using errcode = 'XX000';
  exception when check_violation then null; when raise_exception then
    if sqlerrm not like '%earlier public auction lots%' then raise; end if;
  end;

  begin
    perform public.open_public_auction_lot(
      (select id from public.public_auction_lots where horse_id = '00000000-0000-0000-0000-000000003302')
    );
    raise exception 'an unrevealed future Lot opened while Lot 001 was active' using errcode = 'XX000';
  exception when check_violation then null;
  end;

  begin
    perform public.set_public_auction_event_status(
      (select id from public.public_auction_events where wp_year = 2050),
      'CLOSED'::public.public_auction_event_status
    );
    raise exception 'OPEN Event closed while a Lot was OPEN_WAITING' using errcode = 'XX000';
  exception when check_violation then null; when raise_exception then
    if sqlerrm not like '%active Lot must be closed/settled%' then raise; end if;
  end;
end;
$$;
reset role;

-- Cross-table integrity is enforced even for privileged maintenance code:
-- a Settlement must identify the current Round and Horse of its Lot.
do $$
begin
  begin
    insert into public.public_auction_settlements (
      lot_id, round_id, horse_id, status, winner_owner_id, amount, confirmed_by_user_id
    ) values (
      (select id from public.public_auction_lots where horse_id = '00000000-0000-0000-0000-000000003301'),
      (select current_round_id from public.public_auction_lots where horse_id = '00000000-0000-0000-0000-000000003301'),
      '00000000-0000-0000-0000-000000003302',
      'SOLD'::public.public_auction_settlement_status,
      '00000000-0000-0000-0000-000000003101',
      10000000,
      '00000000-0000-0000-0000-000000003204'
    );
    raise exception 'mismatched Settlement cross references were accepted' using errcode = 'XX000';
  exception when check_violation then null; when raise_exception then
    if sqlerrm not like '%current Round and Horse%' then raise; end if;
  end;
end;
$$;

-- The waiting state has no ten-second clock. Its long deadline is server-side.
do $$
declare v_close timestamptz;
begin
  select round_row.close_at
  into v_close
  from public.public_auction_rounds as round_row
  join public.public_auction_lots as lot on lot.current_round_id = round_row.id
  where lot.horse_id = '00000000-0000-0000-0000-000000003301';
  if v_close is not null then
    raise exception 'OPEN_WAITING unexpectedly started a bidding close clock';
  end if;
end;
$$;

-- First bid at the exact starting price is allowed. The financial summary
-- combines the existing 10m secret freeze and the 20m public winner freeze.
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000003201', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select public.submit_public_auction_bid(
  (select id from public.public_auction_lots where horse_id = '00000000-0000-0000-0000-000000003301'),
  (select current_round_id from public.public_auction_lots where horse_id = '00000000-0000-0000-0000-000000003301'),
  10000000, '00000000-0000-0000-0000-000000003901'
);

do $$
declare v_account bigint; v_secret bigint; v_public bigint; v_total bigint; v_available bigint;
begin
  select account_funds, foal_trade_frozen_funds, public_auction_frozen_funds, total_frozen_funds, available_funds
  into v_account, v_secret, v_public, v_total, v_available
  from public.get_current_owner_financial_summary();
  if (v_account, v_secret, v_public, v_total, v_available)
    <> (100000000, 10000000, 10000000, 20000000, 80000000) then
    raise exception 'combined financial summary is incorrect: %, %, %, %, %', v_account, v_secret, v_public, v_total, v_available;
  end if;
end;
$$;

do $$
declare v_original_close timestamptz; v_retry_close timestamptz; v_bid_count integer;
begin
  select round_row.close_at
  into v_original_close
  from public.public_auction_rounds as round_row
  join public.public_auction_lots as lot on lot.current_round_id = round_row.id
  where lot.horse_id = '00000000-0000-0000-0000-000000003301';

  perform public.submit_public_auction_bid(
    (select id from public.public_auction_lots where horse_id = '00000000-0000-0000-0000-000000003301'),
    (select current_round_id from public.public_auction_lots where horse_id = '00000000-0000-0000-0000-000000003301'),
    10000000, '00000000-0000-0000-0000-000000003901'
  );

  select round_row.close_at,
    (select count(*) from public.public_auction_bids where request_id = '00000000-0000-0000-0000-000000003901')
  into v_retry_close, v_bid_count
  from public.public_auction_rounds as round_row
  join public.public_auction_lots as lot on lot.current_round_id = round_row.id
  where lot.horse_id = '00000000-0000-0000-0000-000000003301';

  if v_retry_close <> v_original_close or v_bid_count <> 1 then
    raise exception 'same request_id and amount was not an idempotent bid retry';
  end if;

  begin
    perform public.submit_public_auction_bid(
      (select id from public.public_auction_lots where horse_id = '00000000-0000-0000-0000-000000003301'),
      (select current_round_id from public.public_auction_lots where horse_id = '00000000-0000-0000-0000-000000003301'),
      10100000, '00000000-0000-0000-0000-000000003901'
    );
    raise exception 'request_id reuse with a different amount was accepted' using errcode = 'XX000';
  exception when check_violation then null; when raise_exception then
    if sqlerrm not like '%idempotency key conflict%' then raise; end if;
  end;
end;
$$;
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000003204', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
do $$
begin
  begin
    perform public.set_public_auction_event_status(
      (select id from public.public_auction_events where wp_year = 2050),
      'CLOSED'::public.public_auction_event_status
    );
    raise exception 'OPEN Event closed while a Lot was BIDDING' using errcode = 'XX000';
  exception when check_violation then null; when raise_exception then
    if sqlerrm not like '%active Lot must be closed/settled%' then raise; end if;
  end;
end;
$$;
reset role;

do $$
declare v_accepted timestamptz; v_close timestamptz;
begin
  select bid.accepted_at, round_row.close_at
  into v_accepted, v_close
  from public.public_auction_bids as bid
  join public.public_auction_rounds as round_row on round_row.id = bid.round_id
  where bid.request_id = '00000000-0000-0000-0000-000000003901';
  if v_close <> v_accepted + interval '10 seconds' then
    raise exception 'first bid close_at was not exactly ten seconds after the final accepted_at';
  end if;
end;
$$;

-- Price rules, self-bidding rejection, and all direct bid mutations are
-- exercised under real authenticated JWT/RLS context.
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000003202', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
do $$
begin
  begin
    perform public.submit_public_auction_bid((select id from public.public_auction_lots where horse_id = '00000000-0000-0000-0000-000000003301'), (select current_round_id from public.public_auction_lots where horse_id = '00000000-0000-0000-0000-000000003301'), 10050000, '00000000-0000-0000-0000-000000003902');
    raise exception 'non-100k auction bid was accepted' using errcode = 'XX000';
  exception when check_violation then null; when raise_exception then
    if sqlerrm not like '%invalid%' then raise; end if;
  end;

  begin
    perform public.submit_public_auction_bid((select id from public.public_auction_lots where horse_id = '00000000-0000-0000-0000-000000003301'), (select current_round_id from public.public_auction_lots where horse_id = '00000000-0000-0000-0000-000000003301'), 10000000, '00000000-0000-0000-0000-000000003903');
    raise exception 'bid below increment was accepted' using errcode = 'XX000';
  exception when check_violation then null; when raise_exception then
    if sqlerrm not like '%minimum increment%' then raise; end if;
  end;
end;
$$;
select public.submit_public_auction_bid(
  (select id from public.public_auction_lots where horse_id = '00000000-0000-0000-0000-000000003301'),
  (select current_round_id from public.public_auction_lots where horse_id = '00000000-0000-0000-0000-000000003301'),
  10100000, '00000000-0000-0000-0000-000000003904'
);
do $$
declare v_public bigint; v_available bigint;
begin
  select public_auction_frozen_funds, available_funds
  into v_public, v_available
  from public.get_current_owner_financial_summary();
  if (v_public, v_available) <> (10100000, 89900000) then
    raise exception 'current winning Owner did not receive the correct public freeze: %, %', v_public, v_available;
  end if;
end;
$$;
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000003202', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
do $$
begin
  begin
    perform public.submit_public_auction_bid((select id from public.public_auction_lots where horse_id = '00000000-0000-0000-0000-000000003301'), (select current_round_id from public.public_auction_lots where horse_id = '00000000-0000-0000-0000-000000003301'), 10200000, '00000000-0000-0000-0000-000000003905');
    raise exception 'current winner bid against themself' using errcode = 'XX000';
  exception when check_violation then null; when raise_exception then
    if sqlerrm not like '%current highest bidder%' then raise; end if;
  end;

  begin
    update public.public_auction_bids set amount = 99999999 where request_id = '00000000-0000-0000-0000-000000003904';
    raise exception 'authenticated PLAYER updated an auction bid' using errcode = 'XX000';
  exception when insufficient_privilege then null;
  end;

  begin
    delete from public.public_auction_bids where request_id = '00000000-0000-0000-0000-000000003904';
    raise exception 'authenticated PLAYER deleted an auction bid' using errcode = 'XX000';
  exception when insufficient_privilege then null;
  end;
end;
$$;
reset role;

-- A jump bid replaces B's public freeze. A can see only A's own aggregate,
-- while C's bid identity and public data remain readable to authenticated users.
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000003203', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select public.submit_public_auction_bid(
  (select id from public.public_auction_lots where horse_id = '00000000-0000-0000-0000-000000003301'),
  (select current_round_id from public.public_auction_lots where horse_id = '00000000-0000-0000-0000-000000003301'),
  20000000, '00000000-0000-0000-0000-000000003906'
);
do $$
begin
  if not exists (select 1 from public.public_auction_events)
    or not exists (select 1 from public.public_auction_bids where amount = 20000000) then
    raise exception 'authenticated PLAYER cannot read public auction data';
  end if;
end;
$$;
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000003201', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
do $$
declare v_public bigint; v_total bigint; v_available bigint;
begin
  select public_auction_frozen_funds, total_frozen_funds, available_funds
  into v_public, v_total, v_available
  from public.get_current_owner_financial_summary();
  if (v_public, v_total, v_available) <> (0, 10000000, 90000000) then
    raise exception 'outbid Owner remains publicly frozen: %, %, %', v_public, v_total, v_available;
  end if;
end;
$$;
reset role;

-- Expired server clocks reject new bids. The GM can then close and normally
-- reopen an unsettled round without erasing bids or its current winner.
update public.public_auction_rounds
set close_at = clock_timestamp() - interval '1 second'
where id = (select current_round_id from public.public_auction_lots where horse_id = '00000000-0000-0000-0000-000000003301');

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000003201', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
do $$
begin
  begin
    perform public.submit_public_auction_bid((select id from public.public_auction_lots where horse_id = '00000000-0000-0000-0000-000000003301'), (select current_round_id from public.public_auction_lots where horse_id = '00000000-0000-0000-0000-000000003301'), 20100000, '00000000-0000-0000-0000-000000003907');
    raise exception 'expired close clock accepted a new bid' using errcode = 'XX000';
  exception when check_violation then null; when raise_exception then
    if sqlerrm not like '%clock has closed%' then raise; end if;
  end;
end;
$$;
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000003204', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select public.close_public_auction_lot(
  (select id from public.public_auction_lots where horse_id = '00000000-0000-0000-0000-000000003301'),
  'Local close after elapsed clock'
);
do $$
begin
  begin
    perform public.reveal_public_auction_lot(
      (select id from public.public_auction_lots where horse_id = '00000000-0000-0000-0000-000000003302')
    );
    raise exception 'a future Lot was revealed while Lot 001 was CLOSED but unsettled' using errcode = 'XX000';
  exception when check_violation then null; when raise_exception then
    if sqlerrm not like '%earlier public auction lots%' then raise; end if;
  end;
end;
$$;
select public.reopen_public_auction_lot(
  (select id from public.public_auction_lots where horse_id = '00000000-0000-0000-0000-000000003301'),
  'Local normal reopen test'
);
reset role;

do $$
declare v_status public.public_auction_round_status; v_price bigint; v_winner uuid; v_bids integer;
begin
  select round_row.status, round_row.current_price, round_row.current_winner_owner_id,
    (select count(*) from public.public_auction_bids as bid where bid.round_id = round_row.id)
  into v_status, v_price, v_winner, v_bids
  from public.public_auction_rounds as round_row
  join public.public_auction_lots as lot on lot.current_round_id = round_row.id
  where lot.horse_id = '00000000-0000-0000-0000-000000003301';
  if v_status <> 'BIDDING' or v_price <> 20000000 or v_winner <> '00000000-0000-0000-0000-000000003103' or v_bids <> 3 then
    raise exception 'normal reopen lost bid/current state';
  end if;
end;
$$;

-- B overtakes after reopen; close and settle sale twice. Settlement idempotency
-- must leave exactly one ledger debit and one Owner assignment.
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000003202', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select public.submit_public_auction_bid(
  (select id from public.public_auction_lots where horse_id = '00000000-0000-0000-0000-000000003301'),
  (select current_round_id from public.public_auction_lots where horse_id = '00000000-0000-0000-0000-000000003301'),
  20100000, '00000000-0000-0000-0000-000000003908'
);
reset role;

update public.public_auction_rounds
set close_at = clock_timestamp() - interval '1 second'
where id = (select current_round_id from public.public_auction_lots where horse_id = '00000000-0000-0000-0000-000000003301');

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000003204', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select public.settle_public_auction_lot(
  (select id from public.public_auction_lots where horse_id = '00000000-0000-0000-0000-000000003301'),
  'Local sale settlement'
);
select public.settle_public_auction_lot(
  (select id from public.public_auction_lots where horse_id = '00000000-0000-0000-0000-000000003301'),
  'Idempotent retry'
);
reset role;

do $$
begin
  if (select owner_id from public.horses where id = '00000000-0000-0000-0000-000000003301') <> '00000000-0000-0000-0000-000000003102'
    or (select life_stage from public.horses where id = '00000000-0000-0000-0000-000000003301') <> 'OWNED_FOAL'::public.horse_life_stage
    or (select count(*) from public.public_auction_settlements where horse_id = '00000000-0000-0000-0000-000000003301') <> 1
    or (select count(*) from public.financial_transactions where source_entity_type = 'PUBLIC_AUCTION_SETTLEMENT') <> 1 then
    raise exception 'SOLD settlement is not idempotent';
  end if;
end;
$$;

-- A rollback request must likewise describe the same Lot, current Round and
-- Settlement rather than merely hold three independently valid UUIDs.
do $$
begin
  begin
    insert into public.public_auction_rollback_requests (
      lot_id, round_id, settlement_id, reason, expected_confirmation
    ) values (
      (select id from public.public_auction_lots where horse_id = '00000000-0000-0000-0000-000000003302'),
      (select current_round_id from public.public_auction_lots where horse_id = '00000000-0000-0000-0000-000000003302'),
      (select id from public.public_auction_settlements where horse_id = '00000000-0000-0000-0000-000000003301'),
      'Invalid cross-reference test',
      'ROLLBACK LOT 002'
    );
    raise exception 'mismatched rollback-request cross references were accepted' using errcode = 'XX000';
  exception when check_violation then null; when raise_exception then
    if sqlerrm not like '%Settlement%' then raise; end if;
  end;
end;
$$;

-- A normal reopen after SOLD must be rejected. The narrow public view contains
-- only final public fields, not internal rollback data.
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000003204', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
do $$
begin
  begin
    perform public.reopen_public_auction_lot((select id from public.public_auction_lots where horse_id = '00000000-0000-0000-0000-000000003301'), 'must fail');
    raise exception 'SOLD lot entered normal reopen' using errcode = 'XX000';
  exception when check_violation then null; when raise_exception then
    if sqlerrm not like '%only an unsettled CLOSED%' then raise; end if;
  end;
end;
$$;
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000003201', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
do $$
begin
  if not exists (
    select 1 from public.public_auction_public_settlements
    where horse_id = '00000000-0000-0000-0000-000000003301'
      and status = 'SOLD'::public.public_auction_settlement_status
      and winner_owner_id = '00000000-0000-0000-0000-000000003102'
      and amount = 20100000
  ) then
    raise exception 'public sale result is missing from the safe public view';
  end if;
end;
$$;
reset role;

-- A final SOLD result permits the next Lot to be revealed. Finish that Lot
-- as PASSED before rolling Lot 001 back, so rollback cannot create two
-- revealed, unfinished Lots.
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000003204', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select public.reveal_public_auction_lot(
  (select id from public.public_auction_lots where horse_id = '00000000-0000-0000-0000-000000003302')
);
select public.open_public_auction_lot(
  (select id from public.public_auction_lots where horse_id = '00000000-0000-0000-0000-000000003302')
);
select public.close_public_auction_lot(
  (select id from public.public_auction_lots where horse_id = '00000000-0000-0000-0000-000000003302'),
  'Complete Lot 002 before testing the Lot 001 rollback'
);
select public.settle_public_auction_pass(
  (select id from public.public_auction_lots where horse_id = '00000000-0000-0000-0000-000000003302'),
  'Local sequential-reveal pass'
);
do $$
begin
  if (select status from public.public_auction_lots where horse_id = '00000000-0000-0000-0000-000000003302')
       <> 'PASSED'::public.public_auction_lot_status
    or (select count(*) from public.public_auction_lots
        where event_id = (select id from public.public_auction_events where wp_year = 2050)
          and revealed_at is not null
          and status not in ('SOLD'::public.public_auction_lot_status, 'PASSED'::public.public_auction_lot_status)) <> 0 then
    raise exception 'a SOLD Lot did not permit exactly one sequential next-Lot reveal';
  end if;
end;
$$;
reset role;

-- SOLD emergency rollback is two-stage. A request alone changes nothing; a
-- correct confirmation adds one compensation ledger entry and starts Round 2.
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000003204', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
do $$
begin
  begin
    perform public.request_public_auction_emergency_rollback((select id from public.public_auction_lots where horse_id = '00000000-0000-0000-0000-000000003301'), '');
    raise exception 'rollback request accepted empty reason' using errcode = 'XX000';
  exception when check_violation then null; when raise_exception then
    if sqlerrm not like '%non-empty reason%' then raise; end if;
  end;
end;
$$;
select public.request_public_auction_emergency_rollback(
  (select id from public.public_auction_lots where horse_id = '00000000-0000-0000-0000-000000003301'),
  'Local sold rollback verification'
);

do $$
begin
  if (select owner_id from public.horses where id = '00000000-0000-0000-0000-000000003301') <> '00000000-0000-0000-0000-000000003102'
    or (select count(*) from public.financial_transactions where source_entity_type = 'PUBLIC_AUCTION_ROLLBACK') <> 0 then
    raise exception 'rollback request performed an irreversible action before confirmation';
  end if;
end;
$$;

do $$
begin
  begin
    perform public.confirm_public_auction_emergency_rollback(
      (select id from public.public_auction_rollback_requests where lot_id = (select id from public.public_auction_lots where horse_id = '00000000-0000-0000-0000-000000003301')),
      'ROLLBACK LOT 999'
    );
    raise exception 'rollback accepted incorrect confirmation text' using errcode = 'XX000';
  exception when check_violation then null; when raise_exception then
    if sqlerrm not like '%confirmation is invalid%' then raise; end if;
  end;
end;
$$;
select public.confirm_public_auction_emergency_rollback(
  (select id from public.public_auction_rollback_requests where lot_id = (select id from public.public_auction_lots where horse_id = '00000000-0000-0000-0000-000000003301')),
  'ROLLBACK LOT 001'
);
select public.confirm_public_auction_emergency_rollback(
  (select id from public.public_auction_rollback_requests where lot_id = (select id from public.public_auction_lots where horse_id = '00000000-0000-0000-0000-000000003301')),
  'ROLLBACK LOT 001'
);
reset role;

do $$
declare v_old_round uuid; v_new_round uuid;
begin
  select settlement.round_id into v_old_round
  from public.public_auction_settlements as settlement
  where settlement.horse_id = '00000000-0000-0000-0000-000000003301';
  select lot.current_round_id into v_new_round
  from public.public_auction_lots as lot
  where lot.horse_id = '00000000-0000-0000-0000-000000003301';
  if v_old_round = v_new_round
    or (select status from public.public_auction_rounds where id = v_old_round) <> 'VOIDED'::public.public_auction_round_status
    or (select status from public.public_auction_rounds where id = v_new_round) <> 'QUEUED'::public.public_auction_round_status
    or (select owner_id from public.horses where id = '00000000-0000-0000-0000-000000003301') is not null
    or (select life_stage from public.horses where id = '00000000-0000-0000-0000-000000003301') <> 'FOAL'::public.horse_life_stage
    or (select revealed_at from public.public_auction_lots where horse_id = '00000000-0000-0000-0000-000000003301') is null
    or (select count(*) from public.financial_transactions where source_entity_type = 'PUBLIC_AUCTION_ROLLBACK') <> 1 then
    raise exception 'SOLD emergency rollback did not preserve/refund/reset exactly once';
  end if;
end;
$$;

-- The rolled-back Lot becomes the earliest unfinished Lot again. A later,
-- still hidden Lot cannot be revealed until Lot 001 has another final result.
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000003204', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
do $$
begin
  begin
    perform public.reveal_public_auction_lot(
      (select id from public.public_auction_lots where horse_id = '00000000-0000-0000-0000-000000003303')
    );
    raise exception 'a later Lot was revealed after Lot 001 emergency rollback' using errcode = 'XX000';
  exception when check_violation then null; when raise_exception then
    if sqlerrm not like '%earlier public auction lots%' then raise; end if;
  end;

  if (select count(*) from public.public_auction_lots
      where event_id = (select id from public.public_auction_events where wp_year = 2050)
        and revealed_at is not null
        and status not in ('SOLD'::public.public_auction_lot_status, 'PASSED'::public.public_auction_lot_status)) <> 1 then
    raise exception 'emergency rollback produced multiple revealed unfinished Lots';
  end if;
end;
$$;

-- A delayed request that still carries Round 1 must never be redirected into
-- the rollback-created Round 2.
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000003204', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select public.open_public_auction_lot((select id from public.public_auction_lots where horse_id = '00000000-0000-0000-0000-000000003301'));
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000003201', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
do $$
declare v_old_round uuid; v_new_round uuid; v_bid_count integer; v_close timestamptz;
begin
  select round_id into v_old_round
  from public.public_auction_settlements
  where horse_id = '00000000-0000-0000-0000-000000003301';
  select current_round_id into v_new_round
  from public.public_auction_lots
  where horse_id = '00000000-0000-0000-0000-000000003301';

  begin
    perform public.submit_public_auction_bid(
      (select id from public.public_auction_lots where horse_id = '00000000-0000-0000-0000-000000003301'),
      v_old_round,
      10000000, '00000000-0000-0000-0000-000000003910'
    );
    raise exception 'stale Round bid was accepted' using errcode = 'XX000';
  exception when check_violation then null; when raise_exception then
    if sqlerrm not like '%stale bid request%' then raise; end if;
  end;

  select count(*), max(close_at)
  into v_bid_count, v_close
  from public.public_auction_bids as bid
  join public.public_auction_rounds as round_row on round_row.id = bid.round_id
  where bid.round_id = v_new_round;

  if v_bid_count <> 0 or v_close is not null then
    raise exception 'stale Round bid mutated the new Round';
  end if;
end;
$$;
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000003204', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select public.close_public_auction_lot((select id from public.public_auction_lots where horse_id = '00000000-0000-0000-0000-000000003301'), 'Close stale-Round verification lot');
do $$
declare v_closed_at timestamptz; v_after_failed_reopen timestamptz;
begin
  select close_at into v_closed_at
  from public.public_auction_rounds
  where id = (select current_round_id from public.public_auction_lots where horse_id = '00000000-0000-0000-0000-000000003301');

  perform public.set_public_auction_event_status(
    (select id from public.public_auction_events where wp_year = 2050),
    'CLOSED'::public.public_auction_event_status
  );

  begin
    perform public.reopen_public_auction_lot(
      (select id from public.public_auction_lots where horse_id = '00000000-0000-0000-0000-000000003301'),
      'must fail while Event is CLOSED'
    );
    raise exception 'a CLOSED Event allowed a normal Lot reopen' using errcode = 'XX000';
  exception when check_violation then null; when raise_exception then
    if sqlerrm not like '%event must be OPEN%' then raise; end if;
  end;

  select close_at into v_after_failed_reopen
  from public.public_auction_rounds
  where id = (select current_round_id from public.public_auction_lots where horse_id = '00000000-0000-0000-0000-000000003301');

  if (select status from public.public_auction_events where wp_year = 2050) <> 'CLOSED'::public.public_auction_event_status
    or (select status from public.public_auction_rounds where id = (select current_round_id from public.public_auction_lots where horse_id = '00000000-0000-0000-0000-000000003301')) <> 'CLOSED'::public.public_auction_round_status
    or v_after_failed_reopen is distinct from v_closed_at then
    raise exception 'a rejected CLOSED-Event reopen changed public-auction state';
  end if;

  perform public.set_public_auction_event_status(
    (select id from public.public_auction_events where wp_year = 2050),
    'OPEN'::public.public_auction_event_status
  );
end;
$$;
select public.reopen_public_auction_lot(
  (select id from public.public_auction_lots where horse_id = '00000000-0000-0000-0000-000000003301'),
  'Event explicitly reopened before normal Lot reopen'
);
select public.close_public_auction_lot(
  (select id from public.public_auction_lots where horse_id = '00000000-0000-0000-0000-000000003301'),
  'Complete Lot 001 after its emergency rollback'
);
select public.settle_public_auction_pass(
  (select id from public.public_auction_lots where horse_id = '00000000-0000-0000-0000-000000003301'),
  'Local post-rollback pass'
);
reset role;

-- A no-bid waiting Lot has only the long timeout. It cannot accept a first
-- bid after that deadline and is not automatically PASSED or discarded.
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000003204', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select public.reveal_public_auction_lot((select id from public.public_auction_lots where horse_id = '00000000-0000-0000-0000-000000003303'));
select public.open_public_auction_lot((select id from public.public_auction_lots where horse_id = '00000000-0000-0000-0000-000000003303'));
reset role;
update public.public_auction_rounds
set no_bid_deadline = clock_timestamp() - interval '1 second'
where id = (select current_round_id from public.public_auction_lots where horse_id = '00000000-0000-0000-0000-000000003303');

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000003201', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
do $$
begin
  begin
    perform public.submit_public_auction_bid((select id from public.public_auction_lots where horse_id = '00000000-0000-0000-0000-000000003303'), (select current_round_id from public.public_auction_lots where horse_id = '00000000-0000-0000-0000-000000003303'), 10000000, '00000000-0000-0000-0000-000000003909');
    raise exception 'expired no-bid deadline accepted a first bid' using errcode = 'XX000';
  exception when check_violation then null; when raise_exception then
    if sqlerrm not like '%no-bid deadline%' then raise; end if;
  end;
end;
$$;
reset role;

do $$
begin
  if (select life_stage from public.horses where id = '00000000-0000-0000-0000-000000003303') <> 'FOAL'::public.horse_life_stage then
    raise exception 'no-bid deadline automatically discarded a Horse';
  end if;
end;
$$;

-- GM confirms a genuinely no-bid Lot as PASSED, then uses the same two-stage
-- rollback to restore its Horse without creating a money compensation.
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000003204', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select public.settle_public_auction_pass((select id from public.public_auction_lots where horse_id = '00000000-0000-0000-0000-000000003303'), 'Local no-bid pass');
select public.request_public_auction_emergency_rollback((select id from public.public_auction_lots where horse_id = '00000000-0000-0000-0000-000000003303'), 'Local passed rollback verification');
select public.confirm_public_auction_emergency_rollback(
  (select id from public.public_auction_rollback_requests where lot_id = (select id from public.public_auction_lots where horse_id = '00000000-0000-0000-0000-000000003303')),
  'ROLLBACK LOT 003'
);
reset role;

do $$
begin
  if (select owner_id from public.horses where id = '00000000-0000-0000-0000-000000003303') is not null
    or (select life_stage from public.horses where id = '00000000-0000-0000-0000-000000003303') <> 'FOAL'::public.horse_life_stage
    or (select count(*) from public.financial_transactions where source_entity_type = 'PUBLIC_AUCTION_ROLLBACK') <> 1
    or not exists (
      select 1 from public.public_auction_rounds as round_row
      join public.public_auction_lots as lot on lot.current_round_id = round_row.id
      where lot.horse_id = '00000000-0000-0000-0000-000000003303'
        and round_row.status = 'QUEUED'::public.public_auction_round_status
    ) then
    raise exception 'PASSED emergency rollback did not restore a clean queued Round';
  end if;
end;
$$;

-- A dedicated Event proves the companion normal path: once Lot 001 is
-- PASSED, Lot 002 may become the only revealed unfinished Lot.
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000003204', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select public.create_public_auction_event(2051, 'PASSED sequential-reveal Event', 100000);
select public.create_public_auction_lot(
  (select id from public.public_auction_events where wp_year = 2051),
  horse_id, lot_number, 10000000, 25000000
)
from (values
  ('00000000-0000-0000-0000-000000003308'::uuid, 1),
  ('00000000-0000-0000-0000-000000003309'::uuid, 2)
) as passed_sequence_lot(horse_id, lot_number);
select public.upsert_public_auction_lot_review(lot.id, slot::smallint, 4::smallint, 'Passed sequence review ' || slot::text)
from public.public_auction_lots as lot
cross join generate_series(1, 5) as slot
where lot.event_id = (select id from public.public_auction_events where wp_year = 2051);
select public.set_public_auction_event_status(
  (select id from public.public_auction_events where wp_year = 2051),
  'OPEN'::public.public_auction_event_status
);
select public.reveal_public_auction_lot(
  (select id from public.public_auction_lots where horse_id = '00000000-0000-0000-0000-000000003308')
);
select public.open_public_auction_lot(
  (select id from public.public_auction_lots where horse_id = '00000000-0000-0000-0000-000000003308')
);
select public.close_public_auction_lot(
  (select id from public.public_auction_lots where horse_id = '00000000-0000-0000-0000-000000003308'),
  'Complete passed sequential-reveal Lot 001'
);
select public.settle_public_auction_pass(
  (select id from public.public_auction_lots where horse_id = '00000000-0000-0000-0000-000000003308'),
  'Passed sequential-reveal settlement'
);
select public.reveal_public_auction_lot(
  (select id from public.public_auction_lots where horse_id = '00000000-0000-0000-0000-000000003309')
);
do $$
begin
  if (select status from public.public_auction_lots where horse_id = '00000000-0000-0000-0000-000000003308') <> 'PASSED'::public.public_auction_lot_status
    or (select revealed_at from public.public_auction_lots where horse_id = '00000000-0000-0000-0000-000000003309') is null
    or (select count(*) from public.public_auction_lots
        where event_id = (select id from public.public_auction_events where wp_year = 2051)
          and revealed_at is not null
          and status not in ('SOLD'::public.public_auction_lot_status, 'PASSED'::public.public_auction_lot_status)) <> 1 then
    raise exception 'a PASSED Lot 001 did not permit exactly one sequential Lot 002 reveal';
  end if;
end;
$$;
reset role;

-- PLAYERs cannot invoke GM entry points, even though GM wrappers use the
-- authenticated role and enforce the final role check internally.
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000003201', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
do $$
begin
  begin
    perform public.reveal_public_auction_lot('00000000-0000-0000-0000-000000003302');
    raise exception 'PLAYER revealed a public-auction Lot' using errcode = 'XX000';
  exception when insufficient_privilege then null;
  end;

  begin
    perform public.open_public_auction_lot((select id from public.public_auction_lots where horse_id = '00000000-0000-0000-0000-000000003302'));
    raise exception 'PLAYER opened a public-auction Lot' using errcode = 'XX000';
  exception when insufficient_privilege then null;
  end;

  begin
    perform public.request_public_auction_emergency_rollback((select id from public.public_auction_lots where horse_id = '00000000-0000-0000-0000-000000003301'), 'not allowed');
    raise exception 'PLAYER requested emergency rollback' using errcode = 'XX000';
  exception when insufficient_privilege then null;
  end;
end;
$$;
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000003204', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
do $$
begin
  begin
    perform public.get_current_owner_financial_summary();
    raise exception 'GM invoked the PLAYER public-auction funds RPC' using errcode = 'XX000';
  exception when insufficient_privilege then null;
  end;
end;
$$;
reset role;

rollback;
