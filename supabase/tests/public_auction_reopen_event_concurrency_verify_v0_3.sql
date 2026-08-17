-- Verify the two sessions cannot leave Event CLOSED with an active Lot.
do $$
declare
  v_lot public.public_auction_lots%rowtype;
  v_round public.public_auction_rounds%rowtype;
begin
  select * into v_lot
  from public.public_auction_lots
  where horse_id = '00000000-0000-0000-0000-000000008301';

  select * into v_round
  from public.public_auction_rounds
  where id = v_lot.current_round_id;

  if (select status from public.public_auction_events where id = v_lot.event_id) <> 'CLOSED'::public.public_auction_event_status
    or v_lot.status <> 'CLOSED'::public.public_auction_lot_status
    or v_round.status <> 'CLOSED'::public.public_auction_round_status
    or v_round.close_at is not null then
    raise exception 'Event-close/reopen race left invalid public-auction state';
  end if;
end;
$$;

begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000008202', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select public.set_public_auction_event_status(
  (select id from public.public_auction_events where wp_year = 2080),
  'OPEN'::public.public_auction_event_status
);
select public.reopen_public_auction_lot(
  (select id from public.public_auction_lots where horse_id = '00000000-0000-0000-0000-000000008301'),
  'Explicit Event reopen restores normal operation'
);
reset role;

do $$
begin
  if (select status from public.public_auction_events where wp_year = 2080) <> 'OPEN'::public.public_auction_event_status
    or (select status from public.public_auction_lots where horse_id = '00000000-0000-0000-0000-000000008301') <> 'OPEN_WAITING'::public.public_auction_lot_status
    or not exists (
      select 1
      from public.public_auction_rounds as round_row
      join public.public_auction_lots as lot on lot.current_round_id = round_row.id
      where lot.horse_id = '00000000-0000-0000-0000-000000008301'
        and round_row.status = 'OPEN_WAITING'::public.public_auction_round_status
        and round_row.no_bid_deadline is not null
        and round_row.close_at is null
    ) then
    raise exception 'explicit Event reopen did not restore a normal Lot reopen path';
  end if;
end;
$$;
commit;
