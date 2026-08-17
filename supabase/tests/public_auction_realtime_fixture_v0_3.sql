-- Persistent local-only fixture for scripts/test-public-auction-realtime.mjs.
-- The verification command resets the local database again after the script.

insert into public.owners (id, display_name, initial_funds)
values
  ('00000000-0000-0000-0000-000000009101', 'Realtime Owner A', 100000000),
  ('00000000-0000-0000-0000-000000009102', 'Realtime Owner B', 100000000);

insert into public.horses (
  id, horse_number, birth_year, foal_name, sex, coat_color,
  sire_name, sire_line, broodmare_sire_name
)
values
(
  '00000000-0000-0000-0000-000000009301',
  99001,
  2099,
  'Realtime Fixture Foal',
  'MALE',
  'BAY',
  'Realtime Sire',
  'Realtime Line',
  'Realtime Broodmare Sire'
),
(
  '00000000-0000-0000-0000-000000009302',
  99002,
  2099,
  'Realtime Future Fixture Foal',
  'FEMALE',
  'CHESTNUT',
  'Realtime Future Sire',
  'Realtime Future Line',
  'Realtime Future Broodmare Sire'
);

insert into public.foal_trade_sessions (id, wp_year, starts_at, ends_at, status)
values (
  '00000000-0000-0000-0000-000000009401',
  2099,
  clock_timestamp() - interval '1 hour',
  clock_timestamp() + interval '1 hour',
  'OPEN'
);

insert into public.foal_trade_lots (id, session_id, horse_id, minimum_price, status)
values
(
  '00000000-0000-0000-0000-000000009501',
  '00000000-0000-0000-0000-000000009401',
  '00000000-0000-0000-0000-000000009301',
  0,
  'UNSOLD'
),
(
  '00000000-0000-0000-0000-000000009502',
  '00000000-0000-0000-0000-000000009401',
  '00000000-0000-0000-0000-000000009302',
  0,
  'UNSOLD'
);

insert into public.foal_trade_settlements (lot_id, session_id, horse_id, status)
values
(
  '00000000-0000-0000-0000-000000009501',
  '00000000-0000-0000-0000-000000009401',
  '00000000-0000-0000-0000-000000009301',
  'UNSOLD'
),
(
  '00000000-0000-0000-0000-000000009502',
  '00000000-0000-0000-0000-000000009401',
  '00000000-0000-0000-0000-000000009302',
  'UNSOLD'
);
