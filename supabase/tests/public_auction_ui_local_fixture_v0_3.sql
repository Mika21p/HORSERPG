-- Disposable local fixture for the v0.3-B browser acceptance workflow.
-- Apply only after the local Auth users documented in the test report exist.

insert into public.owners (id, display_name, initial_funds)
values
  ('00000000-0000-0000-0000-00000000c001', '北方牧场', 100000000),
  ('00000000-0000-0000-0000-00000000c002', '东海赛马', 100000000),
  ('00000000-0000-0000-0000-00000000c003', '西风牧场', 100000000);

insert into public.user_profiles (id, role, owner_id, display_name)
values
  ('00000000-0000-0000-0000-00000000b001', 'GM', null, 'Auction GM'),
  ('00000000-0000-0000-0000-00000000b002', 'PLAYER', '00000000-0000-0000-0000-00000000c001', 'Auction Player A'),
  ('00000000-0000-0000-0000-00000000b003', 'PLAYER', '00000000-0000-0000-0000-00000000c002', 'Auction Player B'),
  ('00000000-0000-0000-0000-00000000b004', 'PLAYER', '00000000-0000-0000-0000-00000000c003', 'Auction Player C');

insert into public.horses (
  id, horse_number, birth_year, foal_name, translated_name, sex, coat_color,
  sire_name, sire_line, broodmare_sire_name
)
values
  ('00000000-0000-0000-0000-00000000d001', 930101, 2101, 'Aurora One', '曙光一号', 'MALE', 'BAY', 'North Star', 'Northern', 'River Mare'),
  ('00000000-0000-0000-0000-00000000d002', 930102, 2101, 'Aurora Two', '曙光二号', 'FEMALE', 'CHESTNUT', 'North Star', 'Northern', 'River Mare'),
  ('00000000-0000-0000-0000-00000000d003', 930103, 2101, 'Aurora Three', '西风三号', 'MALE', 'BLACK', 'East Wind', 'Eastern', 'Summer Mare');

insert into public.foal_trade_sessions (id, wp_year, starts_at, ends_at, status)
values (
  '00000000-0000-0000-0000-00000000e001',
  2101,
  clock_timestamp() - interval '1 hour',
  clock_timestamp() + interval '1 hour',
  'OPEN'
);

insert into public.foal_trade_lots (id, session_id, horse_id, minimum_price, status)
values
  ('00000000-0000-0000-0000-00000000f001', '00000000-0000-0000-0000-00000000e001', '00000000-0000-0000-0000-00000000d001', 0, 'UNSOLD'),
  ('00000000-0000-0000-0000-00000000f002', '00000000-0000-0000-0000-00000000e001', '00000000-0000-0000-0000-00000000d002', 0, 'UNSOLD'),
  ('00000000-0000-0000-0000-00000000f003', '00000000-0000-0000-0000-00000000e001', '00000000-0000-0000-0000-00000000d003', 0, 'UNSOLD');

insert into public.foal_trade_settlements (lot_id, session_id, horse_id, status)
values
  ('00000000-0000-0000-0000-00000000f001', '00000000-0000-0000-0000-00000000e001', '00000000-0000-0000-0000-00000000d001', 'UNSOLD'),
  ('00000000-0000-0000-0000-00000000f002', '00000000-0000-0000-0000-00000000e001', '00000000-0000-0000-0000-00000000d002', 'UNSOLD'),
  ('00000000-0000-0000-0000-00000000f003', '00000000-0000-0000-0000-00000000e001', '00000000-0000-0000-0000-00000000d003', 'UNSOLD');
