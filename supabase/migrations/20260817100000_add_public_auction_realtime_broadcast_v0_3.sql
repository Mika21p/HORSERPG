-- HorseRPG v0.3-A public-auction Realtime notifications.
-- PostgreSQL remains authoritative: broadcasts are deliberately minimal
-- invalidation notices, and clients must re-read their RLS-safe snapshot.

begin;

-- Realtime authorization is evaluated when a private Channel is joined. The
-- managed `realtime.messages` relation is owned by Supabase's internal role,
-- so an application migration may safely add RLS policies but must not try to
-- alter its platform-managed table ACL. There is deliberately no INSERT RLS
-- policy: authenticated browsers cannot broadcast to any topic.
--
-- Keep the receive namespace deliberately narrow: authenticated viewers may
-- receive only public-auction notifications, never arbitrary Realtime topics.

create policy public_auction_realtime_receive_authenticated
on realtime.messages
for select
to authenticated
using (
  (select realtime.topic()) like 'public-auction:%'
);

-- The public auction display is a single, caller-scoped read model.  Keep all
-- relations in one SQL statement so a page refresh cannot combine a pre-bid
-- Round with post-bid Bids (or a historical Round with a new current Round).
-- SECURITY INVOKER deliberately preserves the authenticated caller's existing
-- RLS visibility; this function is a projection, not a privilege bypass.
create function public.get_public_auction_snapshot(p_event_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  with event_row as (
    select event.id, event.status, event.wp_year, event.minimum_increment
    from public.public_auction_events as event
    where event.id = p_event_id
  ),
  revealed_lots as (
    select lot.*
    from public.public_auction_lots as lot
    join event_row as event
      on event.id = lot.event_id
    where lot.revealed_at is not null
  ),
  unfinished_lot as (
    select *
    from revealed_lots
    where status not in (
      'SOLD'::public.public_auction_lot_status,
      'PASSED'::public.public_auction_lot_status
    )
    order by lot_number
    limit 1
  ),
  last_final_lot as (
    select *
    from revealed_lots
    where not exists (select 1 from unfinished_lot)
    order by lot_number desc
    limit 1
  ),
  current_lot as (
    select * from unfinished_lot
    union all
    select * from last_final_lot
  ),
  current_round as (
    select auction_round.*
    from public.public_auction_rounds as auction_round
    join current_lot as lot
      on lot.current_round_id = auction_round.id
    where auction_round.status <> 'VOIDED'::public.public_auction_round_status
  ),
  factor_projection as (
    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'factor_kind', factor.factor_kind,
          'factor_name', factor.factor_name
        )
        order by factor.created_at
      ),
      '[]'::jsonb
    ) as data
    from public.horse_factors as factor
    join current_lot as lot
      on lot.horse_id = factor.horse_id
  ),
  horse_projection as (
    select jsonb_build_object(
      'id', horse.id,
      'horse_number', horse.horse_number,
      'foal_name', horse.foal_name,
      'translated_name', horse.translated_name,
      'sex', horse.sex,
      'coat_color', horse.coat_color,
      'sire_name', horse.sire_name,
      'sire_line', horse.sire_line,
      'broodmare_sire_name', horse.broodmare_sire_name,
      'factors', factor_projection.data
    ) as data
    from public.horses as horse
    join current_lot as lot
      on lot.horse_id = horse.id
    cross join factor_projection
  ),
  review_projection as (
    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'slot', review.slot,
          'stars', review.stars,
          'comment', review.comment
        )
        order by review.slot
      ),
      '[]'::jsonb
    ) as data
    from public.public_auction_lot_reviews as review
    join current_lot as lot
      on lot.id = review.lot_id
  ),
  lot_projection as (
    select jsonb_build_object(
      'id', lot.id,
      'lot_number', lot.lot_number,
      'horse_id', lot.horse_id,
      'starting_price', lot.starting_price,
      'evaluation_value', lot.evaluation_value,
      'revealed_at', lot.revealed_at,
      'status', lot.status,
      'horse', horse_projection.data,
      'reviews', review_projection.data
    ) as data
    from current_lot as lot
    left join horse_projection on true
    cross join review_projection
  ),
  round_projection as (
    select jsonb_build_object(
      'id', auction_round.id,
      'round_number', auction_round.round_number,
      'status', auction_round.status,
      'opened_at', auction_round.opened_at,
      'close_at', auction_round.close_at,
      'no_bid_deadline', auction_round.no_bid_deadline,
      'current_price', auction_round.current_price,
      'current_winner_owner_id', auction_round.current_winner_owner_id
    ) as data
    from current_round as auction_round
  ),
  bid_projection as (
    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'id', bid.id,
          'amount', bid.amount,
          'accepted_at', bid.accepted_at,
          'owner', case
            when owner.id is null then null
            else jsonb_build_object('id', owner.id, 'display_name', owner.display_name)
          end
        )
        order by bid.accepted_at, bid.id
      ),
      '[]'::jsonb
    ) as data
    from public.public_auction_bids as bid
    join current_round as auction_round
      on auction_round.id = bid.round_id
    left join public.owners as owner
      on owner.id = bid.owner_id
  ),
  settlement_projection as (
    select jsonb_build_object(
      'status', settlement.status,
      'winner_owner_id', settlement.winner_owner_id,
      'amount', settlement.amount,
      'confirmed_at', settlement.confirmed_at
    ) as data
    from public.public_auction_public_settlements as settlement
    join current_lot as lot
      on lot.id = settlement.lot_id
  )
  select jsonb_build_object(
    'event', jsonb_build_object(
      'id', event.id,
      'status', event.status,
      'wp_year', event.wp_year,
      'minimum_increment', event.minimum_increment
    ),
    'currentLot', lot_projection.data,
    'currentRound', round_projection.data,
    'bids', bid_projection.data,
    'settlement', settlement_projection.data
  )
  from event_row as event
  left join lot_projection on true
  left join round_projection on true
  cross join bid_projection
  left join settlement_projection on true;
$$;

-- These are trigger-only functions. Every payload identifies the changed
-- public object, but never carries prices, Owners, funds, reviews, internal
-- settlement details, audit data, or rollback reasons.
create function public.broadcast_public_auction_event_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  begin
    perform realtime.send(
      jsonb_build_object(
        'kind', 'EVENT_CHANGED',
        'event_id', new.id
      ),
      'auction_state_changed',
      'public-auction:' || new.id::text,
      true
    );
  exception when others then
    raise warning 'public auction realtime notification failed [%]', sqlstate;
  end;

  return null;
end;
$$;

create function public.broadcast_public_auction_lot_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_kind text;
begin
  -- A future Lot must never have a dedicated broadcast. Once a Lot has been
  -- legitimately revealed, its identifiers are already public through RLS.
  if new.revealed_at is null then
    return null;
  end if;

  v_kind := case
    when old.revealed_at is null then 'LOT_REVEALED'
    else 'LOT_CHANGED'
  end;

  begin
    perform realtime.send(
      jsonb_build_object(
        'kind', v_kind,
        'event_id', new.event_id,
        'lot_id', new.id,
        'round_id', new.current_round_id
      ),
      'auction_state_changed',
      'public-auction:' || new.event_id::text,
      true
    );
  exception when others then
    raise warning 'public auction realtime notification failed [%]', sqlstate;
  end;

  return null;
end;
$$;

create function public.broadcast_public_auction_round_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_event_id uuid;
  v_lot_id uuid;
begin
  -- Only the current Round of a revealed Lot has a PLAYER-readable public
  -- projection. Historical and future Round changes remain silent.
  select lot.event_id, lot.id
  into v_event_id, v_lot_id
  from public.public_auction_lots as lot
  where lot.id = new.lot_id
    and lot.current_round_id = new.id
    and lot.revealed_at is not null;

  if not found then
    return null;
  end if;

  begin
    perform realtime.send(
      jsonb_build_object(
        'kind', 'ROUND_CHANGED',
        'event_id', v_event_id,
        'lot_id', v_lot_id,
        'round_id', new.id
      ),
      'auction_state_changed',
      'public-auction:' || v_event_id::text,
      true
    );
  exception when others then
    raise warning 'public auction realtime notification failed [%]', sqlstate;
  end;

  return null;
end;
$$;

create function public.broadcast_public_auction_bid_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_event_id uuid;
begin
  -- Do not emit a bid notification unless the bid belongs to the currently
  -- readable Round of an already revealed Lot.
  select lot.event_id
  into v_event_id
  from public.public_auction_lots as lot
  where lot.id = new.lot_id
    and lot.current_round_id = new.round_id
    and lot.revealed_at is not null;

  if not found then
    return null;
  end if;

  begin
    perform realtime.send(
      jsonb_build_object(
        'kind', 'BID_ACCEPTED',
        'event_id', v_event_id,
        'lot_id', new.lot_id,
        'round_id', new.round_id,
        'bid_id', new.id
      ),
      'auction_state_changed',
      'public-auction:' || v_event_id::text,
      true
    );
  exception when others then
    raise warning 'public auction realtime notification failed [%]', sqlstate;
  end;

  return null;
end;
$$;

create trigger public_auction_events_broadcast_realtime_change
after update of status on public.public_auction_events
for each row execute function public.broadcast_public_auction_event_change();

create trigger public_auction_lots_broadcast_realtime_change
after update of revealed_at, status, current_round_id, current_price,
  current_winner_owner_id, opened_at, close_at, no_bid_deadline, closed_at
on public.public_auction_lots
for each row execute function public.broadcast_public_auction_lot_change();

create trigger public_auction_rounds_broadcast_realtime_change
after update of status, current_price, current_winner_owner_id, opened_at,
  close_at, no_bid_deadline, closed_at
on public.public_auction_rounds
for each row execute function public.broadcast_public_auction_round_change();

create trigger public_auction_bids_broadcast_realtime_insert
after insert on public.public_auction_bids
for each row execute function public.broadcast_public_auction_bid_insert();

revoke all on function public.broadcast_public_auction_event_change()
  from public, anon, authenticated, service_role;
revoke all on function public.broadcast_public_auction_lot_change()
  from public, anon, authenticated, service_role;
revoke all on function public.broadcast_public_auction_round_change()
  from public, anon, authenticated, service_role;
revoke all on function public.broadcast_public_auction_bid_insert()
  from public, anon, authenticated, service_role;
revoke all on function public.get_public_auction_snapshot(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.get_public_auction_snapshot(uuid) to authenticated;

comment on policy public_auction_realtime_receive_authenticated on realtime.messages is
  'Authenticated users may receive private public-auction Broadcast notifications only.';

comment on function public.get_public_auction_snapshot(uuid) is
  'Atomic caller-RLS public-auction display snapshot for authenticated viewers.';

comment on function public.broadcast_public_auction_event_change() is
  'Trigger-only minimal Realtime invalidation notification for public-auction Event changes.';
comment on function public.broadcast_public_auction_lot_change() is
  'Trigger-only minimal Realtime invalidation notification for revealed public-auction Lot changes.';
comment on function public.broadcast_public_auction_round_change() is
  'Trigger-only minimal Realtime invalidation notification for current revealed public-auction Round changes.';
comment on function public.broadcast_public_auction_bid_insert() is
  'Trigger-only minimal Realtime invalidation notification for accepted public-auction Bids.';

commit;
