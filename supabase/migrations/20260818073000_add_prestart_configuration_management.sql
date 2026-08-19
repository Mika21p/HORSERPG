-- HorseRPG draft configuration management.
-- Draft-only removal is deliberately limited to configuration that has never
-- become player-visible, accepted an intent, or produced a settlement. The
-- affected configuration rows are deleted so their Horses can be configured
-- again; an append-only audit fact remains as the permanent record.

begin;

create function public.remove_foal_trade_draft_lot(
  p_lot_id uuid,
  p_reason text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_session_id uuid;
  v_session public.foal_trade_sessions%rowtype;
  v_lot public.foal_trade_lots%rowtype;
  v_reason text;
begin
  if auth.uid() is null or not public.is_current_user_gm() then
    raise exception 'only a GM may remove a foal-trade draft lot'
      using errcode = '42501';
  end if;

  v_reason := nullif(btrim(p_reason), '');
  if p_lot_id is null or v_reason is null then
    raise exception 'a draft lot and non-empty removal reason are required'
      using errcode = '23514';
  end if;

  select lot.session_id
  into v_session_id
  from public.foal_trade_lots as lot
  where lot.id = p_lot_id;

  if not found then
    raise exception 'foal-trade lot does not exist'
      using errcode = 'P0001';
  end if;

  -- Lock the parent before the Lot. Creation and session-level removal use
  -- this same order, preventing a newly configured Lot from racing removal.
  select *
  into v_session
  from public.foal_trade_sessions
  where id = v_session_id
  for update;

  select *
  into v_lot
  from public.foal_trade_lots
  where id = p_lot_id
    and session_id = v_session.id
  for update;

  if not found
    or v_session.status <> 'DRAFT'::public.foal_trade_session_status
    or clock_timestamp() >= v_session.starts_at then
    raise exception 'foal-trade lots may only be removed from an unstarted DRAFT session'
      using errcode = '23514';
  end if;

  if exists (
    select 1 from public.foal_trade_inquiries where lot_id = v_lot.id
  ) or exists (
    select 1 from public.secret_bid_offers where lot_id = v_lot.id
  ) or exists (
    select 1 from public.secret_bid_offer_history where lot_id = v_lot.id
  ) or exists (
    select 1 from public.foal_trade_settlements where lot_id = v_lot.id
  ) then
    raise exception 'a foal-trade lot with player intent or settlement history cannot be removed'
      using errcode = '23514';
  end if;

  delete from public.foal_trade_lots
  where id = v_lot.id;

  insert into public.audit_logs (
    actor_user_id, actor_role, action, entity_type, entity_id,
    before_data, after_data, reason
  ) values (
    auth.uid(),
    'GM'::public.app_role,
    'FOAL_TRADE_DRAFT_LOT_REMOVED',
    'foal_trade_lots',
    v_lot.id::text,
    jsonb_build_object(
      'session_id', v_lot.session_id,
      'horse_id', v_lot.horse_id,
      'minimum_price', v_lot.minimum_price,
      'status', v_lot.status,
      'created_at', v_lot.created_at
    ),
    jsonb_build_object('removed', true),
    v_reason
  );
end;
$$;

create function public.remove_foal_trade_draft_session(
  p_session_id uuid,
  p_reason text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_session public.foal_trade_sessions%rowtype;
  v_lot_id uuid;
  v_reason text;
begin
  if auth.uid() is null or not public.is_current_user_gm() then
    raise exception 'only a GM may remove a foal-trade draft session'
      using errcode = '42501';
  end if;

  v_reason := nullif(btrim(p_reason), '');
  if p_session_id is null or v_reason is null then
    raise exception 'a draft session and non-empty removal reason are required'
      using errcode = '23514';
  end if;

  select *
  into v_session
  from public.foal_trade_sessions
  where id = p_session_id
  for update;

  if not found then
    raise exception 'foal-trade session does not exist'
      using errcode = 'P0001';
  end if;

  if v_session.status <> 'DRAFT'::public.foal_trade_session_status
    or clock_timestamp() >= v_session.starts_at then
    raise exception 'foal-trade sessions may only be removed while unstarted and DRAFT'
      using errcode = '23514';
  end if;

  for v_lot_id in
    select lot.id
    from public.foal_trade_lots as lot
    where lot.session_id = v_session.id
    order by lot.created_at, lot.id
    for update
  loop
    perform public.remove_foal_trade_draft_lot(v_lot_id, v_reason);
  end loop;

  delete from public.foal_trade_sessions
  where id = v_session.id;

  insert into public.audit_logs (
    actor_user_id, actor_role, action, entity_type, entity_id,
    before_data, after_data, reason
  ) values (
    auth.uid(),
    'GM'::public.app_role,
    'FOAL_TRADE_DRAFT_SESSION_REMOVED',
    'foal_trade_sessions',
    v_session.id::text,
    jsonb_build_object(
      'wp_year', v_session.wp_year,
      'starts_at', v_session.starts_at,
      'ends_at', v_session.ends_at,
      'status', v_session.status
    ),
    jsonb_build_object('removed', true),
    v_reason
  );
end;
$$;

create function public.remove_public_auction_draft_lot(
  p_lot_id uuid,
  p_reason text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_event_id uuid;
  v_event public.public_auction_events%rowtype;
  v_lot public.public_auction_lots%rowtype;
  v_reason text;
  v_round_count integer;
begin
  if auth.uid() is null or not public.is_current_user_gm() then
    raise exception 'only a GM may remove a public-auction draft lot'
      using errcode = '42501';
  end if;

  v_reason := nullif(btrim(p_reason), '');
  if p_lot_id is null or v_reason is null then
    raise exception 'a draft lot and non-empty removal reason are required'
      using errcode = '23514';
  end if;

  select lot.event_id
  into v_event_id
  from public.public_auction_lots as lot
  where lot.id = p_lot_id;

  if not found then
    raise exception 'public-auction lot does not exist'
      using errcode = 'P0001';
  end if;

  -- Configuration creation and removal serialize on Event first, then Lot.
  select *
  into v_event
  from public.public_auction_events
  where id = v_event_id
  for update;

  select *
  into v_lot
  from public.public_auction_lots
  where id = p_lot_id
    and event_id = v_event.id
  for update;

  if not found
    or v_event.status <> 'DRAFT'::public.public_auction_event_status
    or v_lot.status <> 'QUEUED'::public.public_auction_lot_status
    or v_lot.revealed_at is not null
    or v_lot.opened_at is not null
    or v_lot.current_price is not null
    or v_lot.current_winner_owner_id is not null
    or v_lot.close_at is not null
    or v_lot.no_bid_deadline is not null
    or v_lot.closed_at is not null then
    raise exception 'public-auction lots may only be removed from an unstarted DRAFT event'
      using errcode = '23514';
  end if;

  if exists (
    select 1
    from public.public_auction_rounds as round
    where round.lot_id = v_lot.id
      and (
        round.status <> 'QUEUED'::public.public_auction_round_status
        or round.current_price is not null
        or round.current_winner_owner_id is not null
        or round.opened_at is not null
        or round.close_at is not null
        or round.no_bid_deadline is not null
        or round.closed_at is not null
      )
  ) or exists (
    select 1 from public.public_auction_bids where lot_id = v_lot.id
  ) or exists (
    select 1 from public.public_auction_settlements where lot_id = v_lot.id
  ) or exists (
    select 1 from public.public_auction_rollback_requests where lot_id = v_lot.id
  ) then
    raise exception 'a public-auction lot with live or settled history cannot be removed'
      using errcode = '23514';
  end if;

  select count(*)
  into v_round_count
  from public.public_auction_rounds
  where lot_id = v_lot.id;

  delete from public.public_auction_lot_reviews
  where lot_id = v_lot.id;

  -- Break the reverse current_round FK before deleting the draft Rounds.
  update public.public_auction_lots
  set current_round_id = null
  where id = v_lot.id;

  delete from public.public_auction_rounds
  where lot_id = v_lot.id;

  delete from public.public_auction_lots
  where id = v_lot.id;

  insert into public.audit_logs (
    actor_user_id, actor_role, action, entity_type, entity_id,
    before_data, after_data, reason
  ) values (
    auth.uid(),
    'GM'::public.app_role,
    'PUBLIC_AUCTION_DRAFT_LOT_REMOVED',
    'public_auction_lots',
    v_lot.id::text,
    jsonb_build_object(
      'event_id', v_lot.event_id,
      'horse_id', v_lot.horse_id,
      'lot_number', v_lot.lot_number,
      'starting_price', v_lot.starting_price,
      'evaluation_value', v_lot.evaluation_value,
      'round_count', v_round_count
    ),
    jsonb_build_object('removed', true),
    v_reason
  );
end;
$$;

create function public.remove_public_auction_draft_event(
  p_event_id uuid,
  p_reason text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_event public.public_auction_events%rowtype;
  v_lot_id uuid;
  v_reason text;
begin
  if auth.uid() is null or not public.is_current_user_gm() then
    raise exception 'only a GM may remove a public-auction draft event'
      using errcode = '42501';
  end if;

  v_reason := nullif(btrim(p_reason), '');
  if p_event_id is null or v_reason is null then
    raise exception 'a draft event and non-empty removal reason are required'
      using errcode = '23514';
  end if;

  select *
  into v_event
  from public.public_auction_events
  where id = p_event_id
  for update;

  if not found then
    raise exception 'public-auction event does not exist'
      using errcode = 'P0001';
  end if;

  if v_event.status <> 'DRAFT'::public.public_auction_event_status then
    raise exception 'public-auction events may only be removed while DRAFT'
      using errcode = '23514';
  end if;

  for v_lot_id in
    select lot.id
    from public.public_auction_lots as lot
    where lot.event_id = v_event.id
    order by lot.lot_number, lot.id
    for update
  loop
    perform public.remove_public_auction_draft_lot(v_lot_id, v_reason);
  end loop;

  delete from public.public_auction_events
  where id = v_event.id;

  insert into public.audit_logs (
    actor_user_id, actor_role, action, entity_type, entity_id,
    before_data, after_data, reason
  ) values (
    auth.uid(),
    'GM'::public.app_role,
    'PUBLIC_AUCTION_DRAFT_EVENT_REMOVED',
    'public_auction_events',
    v_event.id::text,
    jsonb_build_object(
      'wp_year', v_event.wp_year,
      'name', v_event.name,
      'status', v_event.status,
      'minimum_increment', v_event.minimum_increment
    ),
    jsonb_build_object('removed', true),
    v_reason
  );
end;
$$;

-- The removal surface is authenticated-only at the ACL level. Every function
-- additionally checks the profile-derived GM role and never grants direct
-- DELETE privileges on business tables.
revoke all on function public.remove_foal_trade_draft_lot(uuid, text) from public, anon, authenticated, service_role;
revoke all on function public.remove_foal_trade_draft_session(uuid, text) from public, anon, authenticated, service_role;
revoke all on function public.remove_public_auction_draft_lot(uuid, text) from public, anon, authenticated, service_role;
revoke all on function public.remove_public_auction_draft_event(uuid, text) from public, anon, authenticated, service_role;

grant execute on function public.remove_foal_trade_draft_lot(uuid, text) to authenticated;
grant execute on function public.remove_foal_trade_draft_session(uuid, text) to authenticated;
grant execute on function public.remove_public_auction_draft_lot(uuid, text) to authenticated;
grant execute on function public.remove_public_auction_draft_event(uuid, text) to authenticated;

commit;
