-- Session A holds the Event row lock after a valid OPEN -> CLOSED transition.
begin;
set local lock_timeout = '4s';
set local statement_timeout = '6s';
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000008202', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select public.set_public_auction_event_status(
  (select id from public.public_auction_events where wp_year = 2080),
  'CLOSED'::public.public_auction_event_status
);
select pg_sleep(3);
commit;
