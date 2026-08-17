-- Session A: retry the already-pending request, then retain its locks long
-- enough for Session B to attempt confirmation through the same lock order.
begin;
set local lock_timeout = '4s';
set local statement_timeout = '6s';
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000007202', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select public.request_public_auction_emergency_rollback(
  (select id from public.public_auction_lots where horse_id = '00000000-0000-0000-0000-000000007301'),
  'Rollback lock-order retry'
);
select pg_sleep(3);
commit;
