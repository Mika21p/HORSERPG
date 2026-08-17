-- Session B: starts while Session A is holding Lot/Event/Round/Settlement/
-- Request locks. It must wait rather than form a cyclic deadlock.
begin;
set local lock_timeout = '4s';
set local statement_timeout = '6s';
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000007202', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select public.confirm_public_auction_emergency_rollback(
  (
    select request.id
    from public.public_auction_rollback_requests as request
    join public.public_auction_lots as lot on lot.id = request.lot_id
    where lot.horse_id = '00000000-0000-0000-0000-000000007301'
      and request.status = 'PENDING_CONFIRMATION'::public.public_auction_rollback_request_status
  ),
  'ROLLBACK LOT 001'
);
commit;
