-- Session A obtains the Horse lock, confirms Request A, and deliberately
-- holds the transaction open while Session B attempts a conflicting confirm.

begin;
set local lock_timeout = '4s';
set local statement_timeout = '6s';
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000004702', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select public.confirm_race_entry_request(
  (select id from public.race_entry_requests where player_note = 'concurrent request A'),
  2040, 6::smallint, 2::smallint,
  'CATALOG'::public.race_entry_race_kind, '00000000-0000-0000-0000-000000004901', null, null, null, null
);
select pg_sleep(3);
commit;
