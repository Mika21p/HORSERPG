-- Local-only fixture for the two-session rollback deadlock regression.
-- This script commits deliberately; run a final `npx supabase db reset`
-- after the companion session/verification scripts.

begin;

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
values
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000007201', 'authenticated', 'authenticated', 'rollback-race-player@example.test', 'not-used', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000007202', 'authenticated', 'authenticated', 'rollback-race-gm@example.test', 'not-used', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now());

insert into public.owners (id, display_name, initial_funds)
values ('00000000-0000-0000-0000-000000007101', 'Rollback Race Owner', 100000000);

insert into public.user_profiles (id, role, owner_id, display_name)
values
  ('00000000-0000-0000-0000-000000007201', 'PLAYER', '00000000-0000-0000-0000-000000007101', 'Rollback Race Player'),
  ('00000000-0000-0000-0000-000000007202', 'GM', null, 'Rollback Race GM');

insert into public.horses (
  id, horse_number, birth_year, foal_name, sex, coat_color,
  sire_name, sire_line, broodmare_sire_name
)
values (
  '00000000-0000-0000-0000-000000007301', 70701, 2070, 'Rollback Race Foal',
  'MALE', 'BAY', 'Race Sire', 'Race Line', 'Race Dam Sire'
);

insert into public.foal_trade_sessions (id, wp_year, starts_at, ends_at, status)
values (
  '00000000-0000-0000-0000-000000007401', 2070,
  clock_timestamp() - interval '1 hour', clock_timestamp() + interval '1 hour', 'OPEN'
);

insert into public.foal_trade_lots (id, session_id, horse_id, minimum_price, status)
values (
  '00000000-0000-0000-0000-000000007411',
  '00000000-0000-0000-0000-000000007401',
  '00000000-0000-0000-0000-000000007301', 0, 'UNSOLD'
);

insert into public.foal_trade_settlements (lot_id, session_id, horse_id, status)
values (
  '00000000-0000-0000-0000-000000007411',
  '00000000-0000-0000-0000-000000007401',
  '00000000-0000-0000-0000-000000007301', 'UNSOLD'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000007202', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select public.create_public_auction_event(2070, 'Rollback lock-order Event', 100000);
select public.create_public_auction_lot(
  (select id from public.public_auction_events where wp_year = 2070),
  '00000000-0000-0000-0000-000000007301', 1, 10000000, 25000000
);
select public.upsert_public_auction_lot_review(lot.id, slot::smallint, 5::smallint, 'Rollback race review ' || slot::text)
from public.public_auction_lots as lot
cross join generate_series(1, 5) as slot
where lot.horse_id = '00000000-0000-0000-0000-000000007301';
select public.set_public_auction_event_status(
  (select id from public.public_auction_events where wp_year = 2070),
  'OPEN'::public.public_auction_event_status
);
select public.reveal_public_auction_lot(
  (select id from public.public_auction_lots where horse_id = '00000000-0000-0000-0000-000000007301')
);
select public.open_public_auction_lot(
  (select id from public.public_auction_lots where horse_id = '00000000-0000-0000-0000-000000007301')
);
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000007201', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select public.submit_public_auction_bid(
  (select id from public.public_auction_lots where horse_id = '00000000-0000-0000-0000-000000007301'),
  (select current_round_id from public.public_auction_lots where horse_id = '00000000-0000-0000-0000-000000007301'),
  10000000,
  '00000000-0000-0000-0000-000000007901'
);
reset role;

update public.public_auction_rounds
set close_at = clock_timestamp() - interval '1 second'
where id = (
  select current_round_id
  from public.public_auction_lots
  where horse_id = '00000000-0000-0000-0000-000000007301'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000007202', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select public.settle_public_auction_lot(
  (select id from public.public_auction_lots where horse_id = '00000000-0000-0000-0000-000000007301'),
  'Rollback lock-order settlement'
);
select public.request_public_auction_emergency_rollback(
  (select id from public.public_auction_lots where horse_id = '00000000-0000-0000-0000-000000007301'),
  'Rollback lock-order pending request'
);
reset role;

commit;
