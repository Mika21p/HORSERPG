-- Local-only fixture for the Event-close versus normal-Lot-reopen race.
-- This script commits deliberately; run a final `npx supabase db reset`
-- after the companion session/verification scripts.

begin;

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
values (
  '00000000-0000-0000-0000-000000000000',
  '00000000-0000-0000-0000-000000008202',
  'authenticated', 'authenticated', 'reopen-race-gm@example.test', 'not-used', now(),
  '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()
);

insert into public.user_profiles (id, role, owner_id, display_name)
values (
  '00000000-0000-0000-0000-000000008202',
  'GM'::public.app_role, null, 'Reopen Race GM'
);

insert into public.horses (
  id, horse_number, birth_year, foal_name, sex, coat_color,
  sire_name, sire_line, broodmare_sire_name
)
values (
  '00000000-0000-0000-0000-000000008301', 80801, 2080, 'Reopen Race Foal',
  'MALE', 'BAY', 'Race Sire', 'Race Line', 'Race Dam Sire'
);

insert into public.foal_trade_sessions (id, wp_year, starts_at, ends_at, status)
values (
  '00000000-0000-0000-0000-000000008401', 2080,
  clock_timestamp() - interval '1 hour', clock_timestamp() + interval '1 hour',
  'OPEN'::public.foal_trade_session_status
);

insert into public.foal_trade_lots (id, session_id, horse_id, minimum_price, status)
values (
  '00000000-0000-0000-0000-000000008411',
  '00000000-0000-0000-0000-000000008401',
  '00000000-0000-0000-0000-000000008301', 0,
  'UNSOLD'::public.foal_trade_lot_status
);

insert into public.foal_trade_settlements (lot_id, session_id, horse_id, status)
values (
  '00000000-0000-0000-0000-000000008411',
  '00000000-0000-0000-0000-000000008401',
  '00000000-0000-0000-0000-000000008301',
  'UNSOLD'::public.foal_trade_settlement_status
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000008202', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select public.create_public_auction_event(2080, 'Reopen/Event lock race', 100000);
select public.create_public_auction_lot(
  (select id from public.public_auction_events where wp_year = 2080),
  '00000000-0000-0000-0000-000000008301', 1, 10000000, 25000000
);
select public.upsert_public_auction_lot_review(lot.id, slot::smallint, 5::smallint, 'Reopen race review ' || slot::text)
from public.public_auction_lots as lot
cross join generate_series(1, 5) as slot
where lot.horse_id = '00000000-0000-0000-0000-000000008301';
select public.set_public_auction_event_status(
  (select id from public.public_auction_events where wp_year = 2080),
  'OPEN'::public.public_auction_event_status
);
select public.reveal_public_auction_lot(
  (select id from public.public_auction_lots where horse_id = '00000000-0000-0000-0000-000000008301')
);
select public.open_public_auction_lot(
  (select id from public.public_auction_lots where horse_id = '00000000-0000-0000-0000-000000008301')
);
select public.close_public_auction_lot(
  (select id from public.public_auction_lots where horse_id = '00000000-0000-0000-0000-000000008301'),
  'Prepare closed Lot for Event-close race'
);
reset role;

commit;
