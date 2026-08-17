-- Local-only cross-transaction regression for the v0.3 public-auction
-- migration. Run after the rollback-only public_auction_schema_v0_3.sql test,
-- then run `npx supabase db reset` again: this script intentionally commits
-- its fixture so it can prove that rollback state does not depend on a
-- transaction-local GUC left behind by the original settlement transaction.

-- Transaction A: create three independent Events and finalise one SOLD and
-- two PASSED results. The SALE Event also exercises the strict Event state
-- machine, including the CLOSED -> SETTLED precondition for final Lots.
begin;

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
values
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000006201', 'authenticated', 'authenticated', 'cross-tx-player@example.test', 'not-used', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000006202', 'authenticated', 'authenticated', 'cross-tx-gm@example.test', 'not-used', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now());

insert into public.owners (id, display_name, initial_funds)
values ('00000000-0000-0000-0000-000000006101', 'Cross Transaction Owner', 100000000);

insert into public.user_profiles (id, role, owner_id, display_name)
values
  ('00000000-0000-0000-0000-000000006201', 'PLAYER', '00000000-0000-0000-0000-000000006101', 'Cross Transaction Player'),
  ('00000000-0000-0000-0000-000000006202', 'GM', null, 'Cross Transaction GM');

insert into public.horses (
  id, horse_number, birth_year, foal_name, sex, coat_color,
  sire_name, sire_line, broodmare_sire_name
)
values
  ('00000000-0000-0000-0000-000000006301', 60601, 2060, 'Cross Transaction Sold Foal', 'MALE', 'BAY', 'Cross Sire One', 'Cross Line One', 'Cross Dam Sire One'),
  ('00000000-0000-0000-0000-000000006302', 60602, 2061, 'Cross Transaction Passed Foal', 'FEMALE', 'CHESTNUT', 'Cross Sire Two', 'Cross Line Two', 'Cross Dam Sire Two'),
  ('00000000-0000-0000-0000-000000006303', 60603, 2062, 'Cross Transaction Pending Foal', 'MALE', 'BROWN', 'Cross Sire Three', 'Cross Line Three', 'Cross Dam Sire Three');

insert into public.foal_trade_sessions (id, wp_year, starts_at, ends_at, status)
values
  ('00000000-0000-0000-0000-000000006401', 2060, clock_timestamp() - interval '1 hour', clock_timestamp() + interval '1 hour', 'OPEN'),
  ('00000000-0000-0000-0000-000000006402', 2061, clock_timestamp() - interval '1 hour', clock_timestamp() + interval '1 hour', 'OPEN'),
  ('00000000-0000-0000-0000-000000006403', 2062, clock_timestamp() - interval '1 hour', clock_timestamp() + interval '1 hour', 'OPEN');

insert into public.foal_trade_lots (id, session_id, horse_id, minimum_price, status)
values
  ('00000000-0000-0000-0000-000000006411', '00000000-0000-0000-0000-000000006401', '00000000-0000-0000-0000-000000006301', 0, 'UNSOLD'),
  ('00000000-0000-0000-0000-000000006412', '00000000-0000-0000-0000-000000006402', '00000000-0000-0000-0000-000000006302', 0, 'UNSOLD'),
  ('00000000-0000-0000-0000-000000006413', '00000000-0000-0000-0000-000000006403', '00000000-0000-0000-0000-000000006303', 0, 'UNSOLD');

insert into public.foal_trade_settlements (lot_id, session_id, horse_id, status)
values
  ('00000000-0000-0000-0000-000000006411', '00000000-0000-0000-0000-000000006401', '00000000-0000-0000-0000-000000006301', 'UNSOLD'),
  ('00000000-0000-0000-0000-000000006412', '00000000-0000-0000-0000-000000006402', '00000000-0000-0000-0000-000000006302', 'UNSOLD'),
  ('00000000-0000-0000-0000-000000006413', '00000000-0000-0000-0000-000000006403', '00000000-0000-0000-0000-000000006303', 'UNSOLD');

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000006202', true);
select set_config('request.jwt.claim.role', 'authenticated', true);

-- SALE Event: reject forbidden DRAFT/OPEN transitions, later reject a
-- premature CLOSED -> SETTLED, then finish through the only normal path.
select public.create_public_auction_event(2060, 'Cross transaction SOLD Event', 100000);
do $$
begin
  begin
    perform public.set_public_auction_event_status(
      (select id from public.public_auction_events where wp_year = 2060),
      'CLOSED'::public.public_auction_event_status
    );
    raise exception 'DRAFT -> CLOSED was accepted' using errcode = 'XX000';
  exception when check_violation then null; when raise_exception then
    if sqlerrm not like '%transition%' then raise; end if;
  end;

  begin
    perform public.set_public_auction_event_status(
      (select id from public.public_auction_events where wp_year = 2060),
      'SETTLED'::public.public_auction_event_status
    );
    raise exception 'DRAFT -> SETTLED was accepted' using errcode = 'XX000';
  exception when check_violation then null; when raise_exception then
    if sqlerrm not like '%transition%' then raise; end if;
  end;
end;
$$;
select public.create_public_auction_lot(
  (select id from public.public_auction_events where wp_year = 2060),
  '00000000-0000-0000-0000-000000006301', 1, 10000000, 25000000
);
select public.upsert_public_auction_lot_review(lot.id, slot::smallint, 5::smallint, 'Cross transaction sale review ' || slot::text)
from public.public_auction_lots as lot
cross join generate_series(1, 5) as slot
where lot.horse_id = '00000000-0000-0000-0000-000000006301';
select public.set_public_auction_event_status(
  (select id from public.public_auction_events where wp_year = 2060),
  'OPEN'::public.public_auction_event_status
);
do $$
begin
  begin
    perform public.set_public_auction_event_status(
      (select id from public.public_auction_events where wp_year = 2060),
      'SETTLED'::public.public_auction_event_status
    );
    raise exception 'OPEN -> SETTLED was accepted' using errcode = 'XX000';
  exception when check_violation then null; when raise_exception then
    if sqlerrm not like '%transition%' then raise; end if;
  end;

  begin
    perform public.set_public_auction_event_status(
      (select id from public.public_auction_events where wp_year = 2060),
      'DRAFT'::public.public_auction_event_status
    );
    raise exception 'OPEN -> DRAFT was accepted' using errcode = 'XX000';
  exception when check_violation then null; when raise_exception then
    if sqlerrm not like '%transition%' then raise; end if;
  end;
end;
$$;
select public.reveal_public_auction_lot(
  (select id from public.public_auction_lots where horse_id = '00000000-0000-0000-0000-000000006301')
);
select public.open_public_auction_lot(
  (select id from public.public_auction_lots where horse_id = '00000000-0000-0000-0000-000000006301')
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000006201', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select public.submit_public_auction_bid(
  (select id from public.public_auction_lots where horse_id = '00000000-0000-0000-0000-000000006301'),
  (select current_round_id from public.public_auction_lots where horse_id = '00000000-0000-0000-0000-000000006301'),
  10000000, '00000000-0000-0000-0000-000000006901'
);
reset role;

update public.public_auction_rounds
set close_at = clock_timestamp() - interval '1 second'
where id = (select current_round_id from public.public_auction_lots where horse_id = '00000000-0000-0000-0000-000000006301');

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000006202', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select public.close_public_auction_lot(
  (select id from public.public_auction_lots where horse_id = '00000000-0000-0000-0000-000000006301'),
  'Cross transaction close for state test'
);
select public.set_public_auction_event_status(
  (select id from public.public_auction_events where wp_year = 2060),
  'CLOSED'::public.public_auction_event_status
);
do $$
begin
  begin
    perform public.set_public_auction_event_status(
      (select id from public.public_auction_events where wp_year = 2060),
      'SETTLED'::public.public_auction_event_status
    );
    raise exception 'CLOSED Event with an unfinished Lot became SETTLED' using errcode = 'XX000';
  exception when check_violation then null; when raise_exception then
    if sqlerrm not like '%SOLD or PASSED%' then raise; end if;
  end;
end;
$$;
select public.set_public_auction_event_status(
  (select id from public.public_auction_events where wp_year = 2060),
  'OPEN'::public.public_auction_event_status
);
select public.settle_public_auction_lot(
  (select id from public.public_auction_lots where horse_id = '00000000-0000-0000-0000-000000006301'),
  'Cross transaction sold settlement'
);
select public.set_public_auction_event_status(
  (select id from public.public_auction_events where wp_year = 2060),
  'CLOSED'::public.public_auction_event_status
);
select public.set_public_auction_event_status(
  (select id from public.public_auction_events where wp_year = 2060),
  'SETTLED'::public.public_auction_event_status
);
-- Same-state retries are intentionally harmless no-ops.
select public.set_public_auction_event_status(
  (select id from public.public_auction_events where wp_year = 2060),
  'SETTLED'::public.public_auction_event_status
);
do $$
begin
  begin
    perform public.reopen_public_auction_lot(
      (select id from public.public_auction_lots where horse_id = '00000000-0000-0000-0000-000000006301'),
      'must fail while Event is SETTLED'
    );
    raise exception 'a SETTLED Event allowed a normal Lot reopen' using errcode = 'XX000';
  exception when check_violation then null; when raise_exception then
    if sqlerrm not like '%event must be OPEN%' then raise; end if;
  end;

  begin
    perform public.set_public_auction_event_status(
      (select id from public.public_auction_events where wp_year = 2060),
      'OPEN'::public.public_auction_event_status
    );
    raise exception 'SETTLED -> OPEN was accepted outside emergency rollback' using errcode = 'XX000';
  exception when check_violation then null; when raise_exception then
    if sqlerrm not like '%transition%' then raise; end if;
  end;
end;
$$;

-- PASSED Event: complete normally, commit it as SETTLED, then roll it back
-- only in the next transaction so the PASSED lifecycle guard is cross-TX.
select public.create_public_auction_event(2061, 'Cross transaction PASSED Event', 100000);
select public.create_public_auction_lot(
  (select id from public.public_auction_events where wp_year = 2061),
  '00000000-0000-0000-0000-000000006302', 1, 10000000, 25000000
);
select public.upsert_public_auction_lot_review(lot.id, slot::smallint, 4::smallint, 'Cross transaction pass review ' || slot::text)
from public.public_auction_lots as lot
cross join generate_series(1, 5) as slot
where lot.horse_id = '00000000-0000-0000-0000-000000006302';
select public.set_public_auction_event_status(
  (select id from public.public_auction_events where wp_year = 2061),
  'OPEN'::public.public_auction_event_status
);
select public.reveal_public_auction_lot(
  (select id from public.public_auction_lots where horse_id = '00000000-0000-0000-0000-000000006302')
);
select public.open_public_auction_lot(
  (select id from public.public_auction_lots where horse_id = '00000000-0000-0000-0000-000000006302')
);
select public.close_public_auction_lot(
  (select id from public.public_auction_lots where horse_id = '00000000-0000-0000-0000-000000006302'),
  'Cross transaction no-bid close'
);
select public.set_public_auction_event_status(
  (select id from public.public_auction_events where wp_year = 2061),
  'CLOSED'::public.public_auction_event_status
);
select public.settle_public_auction_pass(
  (select id from public.public_auction_lots where horse_id = '00000000-0000-0000-0000-000000006302'),
  'Cross transaction passed settlement'
);
select public.set_public_auction_event_status(
  (select id from public.public_auction_events where wp_year = 2061),
  'SETTLED'::public.public_auction_event_status
);

-- A second PASSED result verifies that a PENDING rollback request blocks
-- CLOSED -> SETTLED before confirmation. It will be confirmed after commit.
select public.create_public_auction_event(2062, 'Cross transaction pending rollback Event', 100000);
select public.create_public_auction_lot(
  (select id from public.public_auction_events where wp_year = 2062),
  '00000000-0000-0000-0000-000000006303', 1, 10000000, 25000000
);
select public.upsert_public_auction_lot_review(lot.id, slot::smallint, 3::smallint, 'Cross transaction pending review ' || slot::text)
from public.public_auction_lots as lot
cross join generate_series(1, 5) as slot
where lot.horse_id = '00000000-0000-0000-0000-000000006303';
select public.set_public_auction_event_status(
  (select id from public.public_auction_events where wp_year = 2062),
  'OPEN'::public.public_auction_event_status
);
select public.reveal_public_auction_lot(
  (select id from public.public_auction_lots where horse_id = '00000000-0000-0000-0000-000000006303')
);
select public.open_public_auction_lot(
  (select id from public.public_auction_lots where horse_id = '00000000-0000-0000-0000-000000006303')
);
select public.close_public_auction_lot(
  (select id from public.public_auction_lots where horse_id = '00000000-0000-0000-0000-000000006303'),
  'Cross transaction pending no-bid close'
);
select public.set_public_auction_event_status(
  (select id from public.public_auction_events where wp_year = 2062),
  'CLOSED'::public.public_auction_event_status
);
select public.settle_public_auction_pass(
  (select id from public.public_auction_lots where horse_id = '00000000-0000-0000-0000-000000006303'),
  'Cross transaction pending passed settlement'
);
select public.request_public_auction_emergency_rollback(
  (select id from public.public_auction_lots where horse_id = '00000000-0000-0000-0000-000000006303'),
  'Cross transaction pending-state verification'
);
do $$
begin
  begin
    perform public.set_public_auction_event_status(
      (select id from public.public_auction_events where wp_year = 2062),
      'SETTLED'::public.public_auction_event_status
    );
    raise exception 'CLOSED Event with a pending rollback became SETTLED' using errcode = 'XX000';
  exception when check_violation then null; when raise_exception then
    if sqlerrm not like '%pending emergency rollback%' then raise; end if;
  end;
end;
$$;
reset role;
commit;

-- Transaction B: the settlement GUC from transaction A is gone. Both the
-- SOLD and PASSED confirmations must still enter their controlled rollback
-- paths, restore FOAL state, preserve history, and reopen SETTLED Events.
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000006202', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select public.request_public_auction_emergency_rollback(
  (select id from public.public_auction_lots where horse_id = '00000000-0000-0000-0000-000000006301'),
  'Cross transaction SOLD rollback'
);
select public.confirm_public_auction_emergency_rollback(
  (select id from public.public_auction_rollback_requests where lot_id = (select id from public.public_auction_lots where horse_id = '00000000-0000-0000-0000-000000006301')),
  'ROLLBACK LOT 001'
);
select public.request_public_auction_emergency_rollback(
  (select id from public.public_auction_lots where horse_id = '00000000-0000-0000-0000-000000006302'),
  'Cross transaction PASSED rollback'
);
select public.confirm_public_auction_emergency_rollback(
  (select id from public.public_auction_rollback_requests where lot_id = (select id from public.public_auction_lots where horse_id = '00000000-0000-0000-0000-000000006302')),
  'ROLLBACK LOT 001'
);
select public.confirm_public_auction_emergency_rollback(
  (select id from public.public_auction_rollback_requests where lot_id = (select id from public.public_auction_lots where horse_id = '00000000-0000-0000-0000-000000006303')),
  'ROLLBACK LOT 001'
);
reset role;
commit;

-- Transaction C: recovered Events are normally OPEN, and their new Rounds
-- can actually open. The following checks also prove the right Horse state,
-- historical voiding and the exact single sold compensation.
begin;
do $$
begin
  if (select count(*) from public.public_auction_events where wp_year in (2060, 2061, 2062) and status = 'OPEN'::public.public_auction_event_status) <> 3 then
    raise exception 'emergency rollback did not reopen every CLOSED/SETTLED Event';
  end if;

  if exists (
    select 1
    from public.horses
    where id in (
      '00000000-0000-0000-0000-000000006301',
      '00000000-0000-0000-0000-000000006302',
      '00000000-0000-0000-0000-000000006303'
    )
      and (owner_id is not null or life_stage <> 'FOAL'::public.horse_life_stage)
  ) then
    raise exception 'cross-transaction rollback did not restore every Horse to unowned FOAL';
  end if;

  if (select count(*) from public.public_auction_rounds where lot_id in (select id from public.public_auction_lots where horse_id in ('00000000-0000-0000-0000-000000006301', '00000000-0000-0000-0000-000000006302', '00000000-0000-0000-0000-000000006303')) and status = 'VOIDED'::public.public_auction_round_status) <> 3
    or (select count(*) from public.public_auction_rounds as round_row join public.public_auction_lots as lot on lot.current_round_id = round_row.id where lot.horse_id in ('00000000-0000-0000-0000-000000006301', '00000000-0000-0000-0000-000000006302', '00000000-0000-0000-0000-000000006303') and round_row.status = 'QUEUED'::public.public_auction_round_status) <> 3
    or (select count(*) from public.financial_transactions where source_entity_type = 'PUBLIC_AUCTION_ROLLBACK') <> 1
    or (select count(*) from public.audit_logs where action = 'PUBLIC_AUCTION_EVENT_REOPENED_BY_EMERGENCY_ROLLBACK') <> 3 then
    raise exception 'cross-transaction rollback history, compensation, or audit is incorrect';
  end if;
end;
$$;

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000006202', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select public.open_public_auction_lot(
  (select id from public.public_auction_lots where horse_id = '00000000-0000-0000-0000-000000006301')
);
select public.open_public_auction_lot(
  (select id from public.public_auction_lots where horse_id = '00000000-0000-0000-0000-000000006302')
);
reset role;

do $$
begin
  if (select count(*) from public.public_auction_rounds as round_row join public.public_auction_lots as lot on lot.current_round_id = round_row.id where lot.horse_id in ('00000000-0000-0000-0000-000000006301', '00000000-0000-0000-0000-000000006302') and round_row.status = 'OPEN_WAITING'::public.public_auction_round_status) <> 2 then
    raise exception 'a recovered Event could not open its rollback-created Round';
  end if;
end;
$$;
commit;

-- This script intentionally leaves committed local-only fixtures. Run a final
-- `npx supabase db reset` after it so subsequent local work starts clean.
