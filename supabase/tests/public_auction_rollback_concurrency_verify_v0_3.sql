-- Verification after Session A and Session B have both exited successfully.
do $$
declare
  v_lot_id uuid;
  v_original_round_id uuid;
  v_current_round_id uuid;
  v_request public.public_auction_rollback_requests%rowtype;
begin
  select lot.id, settlement.round_id, lot.current_round_id
  into v_lot_id, v_original_round_id, v_current_round_id
  from public.public_auction_lots as lot
  join public.public_auction_settlements as settlement
    on settlement.lot_id = lot.id
  where lot.horse_id = '00000000-0000-0000-0000-000000007301';

  select *
  into v_request
  from public.public_auction_rollback_requests
  where lot_id = v_lot_id;

  if v_request.status <> 'EXECUTED'::public.public_auction_rollback_request_status
    or (select status from public.public_auction_rounds where id = v_original_round_id) <> 'VOIDED'::public.public_auction_round_status
    or (select status from public.public_auction_rounds where id = v_current_round_id) <> 'QUEUED'::public.public_auction_round_status
    or (select count(*) from public.public_auction_rounds where lot_id = v_lot_id) <> 2
    or (select count(*) from public.financial_transactions where source_entity_type = 'PUBLIC_AUCTION_ROLLBACK' and source_entity_id = v_request.id) <> 1
    or (select owner_id from public.horses where id = '00000000-0000-0000-0000-000000007301') is not null
    or (select life_stage from public.horses where id = '00000000-0000-0000-0000-000000007301') <> 'FOAL'::public.horse_life_stage then
    raise exception 'rollback request/confirm concurrency left inconsistent public-auction data';
  end if;
end;
$$;
