-- HorseRPG v0.3 year-end public auction database layer.
-- This migration is local-only until separately reviewed for deployment.

begin;

create type public.public_auction_event_status as enum (
  'DRAFT',
  'OPEN',
  'CLOSED',
  'SETTLED'
);

create type public.public_auction_lot_status as enum (
  'QUEUED',
  'OPEN_WAITING',
  'BIDDING',
  'CLOSED',
  'SOLD',
  'PASSED'
);

create type public.public_auction_round_status as enum (
  'QUEUED',
  'OPEN_WAITING',
  'BIDDING',
  'CLOSED',
  'SOLD',
  'PASSED',
  'VOIDED'
);

create type public.public_auction_settlement_status as enum ('SOLD', 'PASSED');

create type public.public_auction_rollback_request_status as enum (
  'PENDING_CONFIRMATION',
  'EXECUTED',
  'CANCELLED',
  'EXPIRED'
);

create table public.public_auction_events (
  id uuid primary key default gen_random_uuid(),
  wp_year integer not null unique check (wp_year > 0),
  name text not null check (length(btrim(name)) > 0),
  status public.public_auction_event_status not null default 'DRAFT'::public.public_auction_event_status,
  minimum_increment bigint not null default 100000 check (
    minimum_increment >= 100000
    and minimum_increment % 100000 = 0
  ),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.public_auction_lots (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.public_auction_events(id) on delete restrict,
  horse_id uuid not null unique references public.horses(id) on delete restrict,
  lot_number integer not null check (lot_number > 0),
  starting_price bigint not null check (starting_price >= 0 and starting_price % 100000 = 0),
  evaluation_value bigint not null check (evaluation_value >= 0),
  revealed_at timestamptz,
  status public.public_auction_lot_status not null default 'QUEUED'::public.public_auction_lot_status,
  current_price bigint check (current_price is null or (current_price >= 0 and current_price % 100000 = 0)),
  current_winner_owner_id uuid references public.owners(id) on delete restrict,
  opened_at timestamptz,
  close_at timestamptz,
  no_bid_deadline timestamptz,
  closed_at timestamptz,
  current_round_id uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint public_auction_lots_event_lot_number_unique unique (event_id, lot_number),
  constraint public_auction_lots_price_winner_pair_check check (
    (current_price is null and current_winner_owner_id is null)
    or (current_price is not null and current_winner_owner_id is not null)
  )
);

create index public_auction_lots_event_status_idx
  on public.public_auction_lots (event_id, status, lot_number);

-- At most one Lot in an Event may be accepting or waiting for bids at a time.
create unique index public_auction_events_one_active_lot_idx
  on public.public_auction_lots (event_id)
  where status in (
    'OPEN_WAITING'::public.public_auction_lot_status,
    'BIDDING'::public.public_auction_lot_status
  );

create table public.public_auction_rounds (
  id uuid primary key default gen_random_uuid(),
  lot_id uuid not null references public.public_auction_lots(id) on delete restrict,
  round_number integer not null check (round_number > 0),
  status public.public_auction_round_status not null default 'QUEUED'::public.public_auction_round_status,
  current_price bigint check (current_price is null or (current_price >= 0 and current_price % 100000 = 0)),
  current_winner_owner_id uuid references public.owners(id) on delete restrict,
  opened_at timestamptz,
  close_at timestamptz,
  no_bid_deadline timestamptz,
  closed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint public_auction_rounds_lot_round_number_unique unique (lot_id, round_number),
  constraint public_auction_rounds_price_winner_pair_check check (
    (current_price is null and current_winner_owner_id is null)
    or (current_price is not null and current_winner_owner_id is not null)
  )
);

alter table public.public_auction_lots
  add constraint public_auction_lots_current_round_fk
  foreign key (current_round_id)
  references public.public_auction_rounds(id)
  on delete restrict;

create index public_auction_rounds_lot_status_idx
  on public.public_auction_rounds (lot_id, status, round_number desc);

-- A Lot may have historical and rollback-created Rounds, but only one of
-- those Rounds can ever be actively accepting or waiting for bids.
create unique index public_auction_rounds_one_active_round_per_lot_idx
  on public.public_auction_rounds (lot_id)
  where status in (
    'OPEN_WAITING'::public.public_auction_round_status,
    'BIDDING'::public.public_auction_round_status
  );

create index public_auction_rounds_current_winner_idx
  on public.public_auction_rounds (current_winner_owner_id)
  where current_winner_owner_id is not null
    and status in (
      'BIDDING'::public.public_auction_round_status,
      'CLOSED'::public.public_auction_round_status
    );

create table public.public_auction_lot_reviews (
  id uuid primary key default gen_random_uuid(),
  lot_id uuid not null references public.public_auction_lots(id) on delete restrict,
  slot smallint not null check (slot between 1 and 5),
  stars smallint not null check (stars between 1 and 5),
  comment text not null check (length(btrim(comment)) > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint public_auction_lot_reviews_slot_unique unique (lot_id, slot)
);

create index public_auction_lot_reviews_lot_id_idx
  on public.public_auction_lot_reviews (lot_id, slot);

create table public.public_auction_bids (
  id uuid primary key default gen_random_uuid(),
  lot_id uuid not null references public.public_auction_lots(id) on delete restrict,
  round_id uuid not null references public.public_auction_rounds(id) on delete restrict,
  owner_id uuid not null references public.owners(id) on delete restrict,
  amount bigint not null check (amount >= 0 and amount % 100000 = 0),
  request_id uuid not null,
  accepted_at timestamptz not null default clock_timestamp(),
  created_at timestamptz not null default now(),
  constraint public_auction_bids_owner_round_request_unique unique (owner_id, round_id, request_id)
);

create index public_auction_bids_round_accepted_at_idx
  on public.public_auction_bids (round_id, accepted_at, id);

create index public_auction_bids_lot_round_amount_idx
  on public.public_auction_bids (lot_id, round_id, amount desc, accepted_at asc, id asc);

create table public.public_auction_settlements (
  id uuid primary key default gen_random_uuid(),
  lot_id uuid not null references public.public_auction_lots(id) on delete restrict,
  round_id uuid not null unique references public.public_auction_rounds(id) on delete restrict,
  horse_id uuid not null references public.horses(id) on delete restrict,
  status public.public_auction_settlement_status not null,
  winner_owner_id uuid references public.owners(id) on delete restrict,
  amount bigint check (amount is null or (amount >= 0 and amount % 100000 = 0)),
  confirmed_by_user_id uuid references auth.users(id) on delete set null,
  confirmed_at timestamptz not null default clock_timestamp(),
  reason text,
  rolled_back_at timestamptz,
  rolled_back_by_user_id uuid references auth.users(id) on delete set null,
  rollback_request_id uuid,
  created_at timestamptz not null default now(),
  constraint public_auction_settlements_outcome_check check (
    (status = 'SOLD'::public.public_auction_settlement_status
      and winner_owner_id is not null
      and amount is not null)
    or
    (status = 'PASSED'::public.public_auction_settlement_status
      and winner_owner_id is null
      and amount is null)
  )
);

create index public_auction_settlements_lot_id_idx
  on public.public_auction_settlements (lot_id, confirmed_at);

create table public.public_auction_rollback_requests (
  id uuid primary key default gen_random_uuid(),
  lot_id uuid not null references public.public_auction_lots(id) on delete restrict,
  round_id uuid not null references public.public_auction_rounds(id) on delete restrict,
  settlement_id uuid not null references public.public_auction_settlements(id) on delete restrict,
  requested_by_user_id uuid references auth.users(id) on delete set null,
  reason text not null check (length(btrim(reason)) > 0),
  status public.public_auction_rollback_request_status not null default 'PENDING_CONFIRMATION'::public.public_auction_rollback_request_status,
  expected_confirmation text not null check (length(btrim(expected_confirmation)) > 0),
  requested_at timestamptz not null default clock_timestamp(),
  confirmed_by_user_id uuid references auth.users(id) on delete set null,
  confirmed_at timestamptz,
  executed_at timestamptz,
  compensation_transaction_id uuid references public.financial_transactions(id) on delete restrict,
  new_round_id uuid references public.public_auction_rounds(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint public_auction_rollback_requests_execution_check check (
    (status = 'EXECUTED'::public.public_auction_rollback_request_status
      and confirmed_at is not null
      and executed_at is not null
      and new_round_id is not null)
    or
    (status <> 'EXECUTED'::public.public_auction_rollback_request_status
      and executed_at is null
      and new_round_id is null)
  )
);

alter table public.public_auction_settlements
  add constraint public_auction_settlements_rollback_request_fk
  foreign key (rollback_request_id)
  references public.public_auction_rollback_requests(id)
  on delete restrict;

create unique index public_auction_rollback_one_pending_per_settlement_idx
  on public.public_auction_rollback_requests (settlement_id)
  where status = 'PENDING_CONFIRMATION'::public.public_auction_rollback_request_status;

create unique index public_auction_rollback_one_executed_per_settlement_idx
  on public.public_auction_rollback_requests (settlement_id)
  where status = 'EXECUTED'::public.public_auction_rollback_request_status;

create unique index financial_transactions_public_auction_settlement_once_idx
  on public.financial_transactions (source_entity_type, source_entity_id)
  where source_entity_type = 'PUBLIC_AUCTION_SETTLEMENT'
    and source_entity_id is not null;

create unique index financial_transactions_public_auction_rollback_once_idx
  on public.financial_transactions (source_entity_type, source_entity_id)
  where source_entity_type = 'PUBLIC_AUCTION_ROLLBACK'
    and source_entity_id is not null;

create function public.enforce_public_auction_lot_horse_eligibility()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_event_year integer;
  v_horse_birth_year integer;
  v_horse_owner_id uuid;
  v_horse_life_stage public.horse_life_stage;
begin
  select wp_year
  into v_event_year
  from public.public_auction_events
  where id = new.event_id
  for key share;

  if not found then
    raise exception 'public auction event does not exist'
      using errcode = '23503';
  end if;

  select birth_year, owner_id, life_stage
  into v_horse_birth_year, v_horse_owner_id, v_horse_life_stage
  from public.horses
  where id = new.horse_id
  for update;

  if not found then
    raise exception 'public auction horse does not exist'
      using errcode = '23503';
  end if;

  if v_horse_birth_year <> v_event_year
    or v_horse_owner_id is not null
    or v_horse_life_stage <> 'FOAL'::public.horse_life_stage
    or not exists (
      select 1
      from public.foal_trade_lots as foal_lot
      join public.foal_trade_sessions as foal_session
        on foal_session.id = foal_lot.session_id
      join public.foal_trade_settlements as foal_settlement
        on foal_settlement.lot_id = foal_lot.id
      where foal_lot.horse_id = new.horse_id
        and foal_session.wp_year = v_event_year
        and foal_lot.status = 'UNSOLD'::public.foal_trade_lot_status
        and foal_settlement.status = 'UNSOLD'::public.foal_trade_settlement_status
    ) then
    raise exception 'public auction requires an unowned FOAL from an UNSOLD foal trade lot in the same WP year'
      using errcode = '23514';
  end if;

  return new;
end;
$$;

create trigger public_auction_lots_enforce_horse_eligibility
before insert or update of event_id, horse_id on public.public_auction_lots
for each row execute function public.enforce_public_auction_lot_horse_eligibility();

create function public.enforce_public_auction_current_round_integrity()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.current_round_id is not null and not exists (
    select 1
    from public.public_auction_rounds
    where id = new.current_round_id
      and lot_id = new.id
  ) then
    raise exception 'a public auction current round must belong to its lot'
      using errcode = '23514';
  end if;

  return new;
end;
$$;

create trigger public_auction_lots_enforce_current_round_integrity
before insert or update of current_round_id on public.public_auction_lots
for each row execute function public.enforce_public_auction_current_round_integrity();

create function public.apply_public_auction_round_state_to_lot(p_round_id uuid)
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_round public.public_auction_rounds%rowtype;
begin
  select *
  into v_round
  from public.public_auction_rounds
  where id = p_round_id;

  if not found then
    raise exception 'public auction round does not exist'
      using errcode = '23503';
  end if;

  update public.public_auction_lots
  set status = case v_round.status
      when 'QUEUED'::public.public_auction_round_status then 'QUEUED'::public.public_auction_lot_status
      when 'OPEN_WAITING'::public.public_auction_round_status then 'OPEN_WAITING'::public.public_auction_lot_status
      when 'BIDDING'::public.public_auction_round_status then 'BIDDING'::public.public_auction_lot_status
      when 'CLOSED'::public.public_auction_round_status then 'CLOSED'::public.public_auction_lot_status
      when 'SOLD'::public.public_auction_round_status then 'SOLD'::public.public_auction_lot_status
      when 'PASSED'::public.public_auction_round_status then 'PASSED'::public.public_auction_lot_status
      else 'QUEUED'::public.public_auction_lot_status
    end,
    current_price = v_round.current_price,
    current_winner_owner_id = v_round.current_winner_owner_id,
    opened_at = v_round.opened_at,
    close_at = v_round.close_at,
    no_bid_deadline = v_round.no_bid_deadline,
    closed_at = v_round.closed_at
  where current_round_id = p_round_id;
end;
$$;

create function public.sync_public_auction_lot_after_round_change()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  perform public.apply_public_auction_round_state_to_lot(new.id);
  return new;
end;
$$;

create trigger public_auction_rounds_sync_current_lot
after insert or update of status, current_price, current_winner_owner_id, opened_at, close_at, no_bid_deadline, closed_at
on public.public_auction_rounds
for each row execute function public.sync_public_auction_lot_after_round_change();

create function public.sync_public_auction_lot_after_current_round_change()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.current_round_id is not null then
    perform public.apply_public_auction_round_state_to_lot(new.current_round_id);
  end if;
  return new;
end;
$$;

create trigger public_auction_lots_sync_after_current_round_change
after insert or update of current_round_id on public.public_auction_lots
for each row execute function public.sync_public_auction_lot_after_current_round_change();

create function public.enforce_public_auction_bid_integrity()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_round_lot_id uuid;
begin
  select lot_id
  into v_round_lot_id
  from public.public_auction_rounds
  where id = new.round_id
  for key share;

  if not found or v_round_lot_id <> new.lot_id then
    raise exception 'public auction bid must match its round and lot'
      using errcode = '23514';
  end if;

  new.accepted_at = clock_timestamp();
  return new;
end;
$$;

create trigger public_auction_bids_enforce_integrity
before insert on public.public_auction_bids
for each row execute function public.enforce_public_auction_bid_integrity();

create function public.prevent_public_auction_bid_mutation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'public_auction_bids are append-only and cannot be changed or deleted'
    using errcode = '55000';
end;
$$;

create trigger public_auction_bids_prevent_mutation
before update or delete on public.public_auction_bids
for each row execute function public.prevent_public_auction_bid_mutation();

-- Foreign keys alone do not prove that a Settlement references the Round and
-- Horse of its Lot. These guards keep every cross-table identifier coherent,
-- including for privileged maintenance code.
create function public.enforce_public_auction_settlement_integrity()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  perform 1
  from public.public_auction_lots as lot
  join public.public_auction_rounds as auction_round
    on auction_round.id = new.round_id
  where lot.id = new.lot_id
    and lot.horse_id = new.horse_id
    and lot.current_round_id = new.round_id
    and auction_round.lot_id = lot.id
  for key share of lot, auction_round;

  if not found then
    raise exception 'public auction settlement must match the current Round and Horse of its Lot'
      using errcode = '23514';
  end if;

  return new;
end;
$$;

create trigger public_auction_settlements_enforce_integrity
before insert or update of lot_id, round_id, horse_id on public.public_auction_settlements
for each row execute function public.enforce_public_auction_settlement_integrity();

create function public.enforce_public_auction_rollback_request_integrity()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  perform 1
  from public.public_auction_lots as lot
  join public.public_auction_rounds as auction_round
    on auction_round.id = new.round_id
  join public.public_auction_settlements as settlement
    on settlement.id = new.settlement_id
  where lot.id = new.lot_id
    and lot.current_round_id = new.round_id
    and auction_round.lot_id = lot.id
    and settlement.lot_id = lot.id
    and settlement.round_id = auction_round.id
  for key share of lot, auction_round, settlement;

  if not found then
    raise exception 'public auction rollback request must match its current Lot, Round, and Settlement'
      using errcode = '23514';
  end if;

  return new;
end;
$$;

create trigger public_auction_rollback_requests_enforce_integrity
before insert or update of lot_id, round_id, settlement_id on public.public_auction_rollback_requests
for each row execute function public.enforce_public_auction_rollback_request_integrity();

create trigger public_auction_events_set_updated_at
before update on public.public_auction_events
for each row execute function public.set_updated_at();

create trigger public_auction_lots_set_updated_at
before update on public.public_auction_lots
for each row execute function public.set_updated_at();

create trigger public_auction_rounds_set_updated_at
before update on public.public_auction_rounds
for each row execute function public.set_updated_at();

create trigger public_auction_lot_reviews_set_updated_at
before update on public.public_auction_lot_reviews
for each row execute function public.set_updated_at();

create trigger public_auction_rollback_requests_set_updated_at
before update on public.public_auction_rollback_requests
for each row execute function public.set_updated_at();

-- Public-auction bids must be included in the existing foal-trade freeze
-- path too. This extra trigger protects the published v0.2 bid RPC without
-- modifying its historical migration or changing its signature.
create function public.enforce_secret_bid_offer_combined_freeze()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_account_funds bigint;
  v_other_secret_frozen bigint;
  v_public_auction_frozen bigint;
begin
  if new.status <> 'ACTIVE'::public.secret_bid_offer_status then
    return new;
  end if;

  select initial_funds
  into v_account_funds
  from public.owners
  where id = new.owner_id
  for update;

  if not found then
    raise exception 'secret bid Owner does not exist'
      using errcode = '23503';
  end if;

  select v_account_funds + coalesce(sum(amount), 0)
  into v_account_funds
  from public.financial_transactions
  where owner_id = new.owner_id;

  select coalesce(sum(amount), 0)
  into v_other_secret_frozen
  from public.secret_bid_offers
  where owner_id = new.owner_id
    and status = 'ACTIVE'::public.secret_bid_offer_status
    and (tg_op = 'INSERT' or id <> new.id);

  select coalesce(sum(round_row.current_price), 0)
  into v_public_auction_frozen
  from public.public_auction_rounds as round_row
  join public.public_auction_lots as lot
    on lot.current_round_id = round_row.id
  where round_row.current_winner_owner_id = new.owner_id
    and round_row.status in (
      'BIDDING'::public.public_auction_round_status,
      'CLOSED'::public.public_auction_round_status
    );

  if v_account_funds - v_other_secret_frozen - v_public_auction_frozen - new.amount < 0 then
    raise exception 'secret bid would exceed available funds after public auction freezes'
      using errcode = 'P0001';
  end if;

  return new;
end;
$$;

create trigger secret_bid_offers_enforce_combined_freeze
before insert or update of owner_id, amount, status on public.secret_bid_offers
for each row execute function public.enforce_secret_bid_offer_combined_freeze();

-- Extend the published horse guards without changing their historical
-- migrations. The setting contains a concrete settlement id and is validated
-- below against the Horse, Round, Lot, Owner, and settlement lifecycle.
create or replace function public.prevent_horse_owner_reassignment()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if old.owner_id is not null and new.owner_id is distinct from old.owner_id then
    if new.owner_id is null
      and nullif(current_setting('horserpg.public_auction_rollback', true), '') is not null then
      return new;
    end if;

    raise exception 'horse ownership cannot be reassigned directly'
      using errcode = '23514';
  end if;
  return new;
end;
$$;

create or replace function public.prevent_foal_trade_lot_horse_direct_assignment()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if old.owner_id is null
    and new.owner_id is not null
    and exists (
      select 1
      from public.foal_trade_lots
      where horse_id = old.id
    )
    and current_setting('horserpg.foal_trade_settlement', true) is distinct from 'on'
    and nullif(current_setting('horserpg.public_auction_settlement', true), '') is null then
    raise exception 'a foal trade lot horse may only receive an Owner through a controlled settlement'
      using errcode = '23514';
  end if;

  return new;
end;
$$;

create function public.enforce_public_auction_horse_lifecycle()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_settlement_context_id text;
  v_pass_context_id text;
  v_rollback_context_id text;
  v_settlement public.public_auction_settlements%rowtype;
  v_round_lot_id uuid;
  v_is_current_round boolean;
begin
  if not exists (
    select 1
    from public.public_auction_lots
    where horse_id = old.id
  ) then
    return new;
  end if;

  v_settlement_context_id := nullif(current_setting('horserpg.public_auction_settlement', true), '');

  if old.owner_id is null and new.owner_id is not null then
    select settlement.*
    into v_settlement
    from public.public_auction_settlements as settlement
    where settlement.id::text = v_settlement_context_id
    for key share;

    select lot_id
    into v_round_lot_id
    from public.public_auction_rounds
    where id = v_settlement.round_id
    for key share;

    select lot.current_round_id = v_settlement.round_id
    into v_is_current_round
    from public.public_auction_lots as lot
    where lot.id = v_settlement.lot_id
    for key share;

    if not found
      or v_settlement.status <> 'SOLD'::public.public_auction_settlement_status
      or v_settlement.rolled_back_at is not null
      or v_settlement.horse_id <> old.id
      or v_settlement.winner_owner_id <> new.owner_id
      or v_round_lot_id <> v_settlement.lot_id
      or v_is_current_round is not true
      or new.life_stage <> 'OWNED_FOAL'::public.horse_life_stage then
      raise exception 'public auction Horse assignment requires its matching controlled settlement'
        using errcode = '23514';
    end if;

    return new;
  end if;

  v_rollback_context_id := nullif(current_setting('horserpg.public_auction_rollback', true), '');

  if old.owner_id is not null and new.owner_id is null then
    select settlement.*
    into v_settlement
    from public.public_auction_settlements as settlement
    where settlement.id::text = v_rollback_context_id
    for key share;

    if not found
      or v_settlement.status <> 'SOLD'::public.public_auction_settlement_status
      or v_settlement.rolled_back_at is null
      or v_settlement.horse_id <> old.id
      or v_settlement.winner_owner_id <> old.owner_id
      or new.life_stage <> 'FOAL'::public.horse_life_stage then
      raise exception 'public auction Horse ownership rollback requires its matching executed settlement'
        using errcode = '23514';
    end if;

    return new;
  end if;

  v_pass_context_id := nullif(current_setting('horserpg.public_auction_pass', true), '');

  if old.owner_id is null
    and new.owner_id is null
    and old.life_stage = 'FOAL'::public.horse_life_stage
    and new.life_stage = 'DISCARDED'::public.horse_life_stage then
    select settlement.*
    into v_settlement
    from public.public_auction_settlements as settlement
    where settlement.id::text = v_pass_context_id
    for key share;

    if not found
      or v_settlement.status <> 'PASSED'::public.public_auction_settlement_status
      or v_settlement.rolled_back_at is not null
      or v_settlement.horse_id <> old.id then
      raise exception 'public auction PASSED Horse transition requires its matching controlled settlement'
        using errcode = '23514';
    end if;

    return new;
  end if;

  if old.owner_id is null
    and new.owner_id is null
    and old.life_stage = 'DISCARDED'::public.horse_life_stage
    and new.life_stage = 'FOAL'::public.horse_life_stage then
    v_rollback_context_id := nullif(current_setting('horserpg.public_auction_rollback', true), '');

    select settlement.*
    into v_settlement
    from public.public_auction_settlements as settlement
    where settlement.id::text = v_rollback_context_id
    for key share;

    if not found
      or v_settlement.status <> 'PASSED'::public.public_auction_settlement_status
      or v_settlement.rolled_back_at is null
      or v_settlement.horse_id <> old.id then
      raise exception 'public auction PASSED rollback requires its matching executed settlement'
        using errcode = '23514';
    end if;
  end if;

  return new;
end;
$$;

create trigger horses_enforce_public_auction_lifecycle
before update of owner_id, life_stage on public.horses
for each row execute function public.enforce_public_auction_horse_lifecycle();

create function public.create_public_auction_event(
  p_wp_year integer,
  p_name text,
  p_minimum_increment bigint default 100000
)
returns public.public_auction_events
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_event public.public_auction_events%rowtype;
begin
  if auth.uid() is null or not public.is_current_user_gm() then
    raise exception 'only a GM may create a public auction event'
      using errcode = '42501';
  end if;

  if p_wp_year is null or p_wp_year <= 0
    or nullif(btrim(p_name), '') is null
    or p_minimum_increment is null
    or p_minimum_increment < 100000
    or p_minimum_increment % 100000 <> 0 then
    raise exception 'public auction event fields are invalid'
      using errcode = '23514';
  end if;

  insert into public.public_auction_events (wp_year, name, minimum_increment)
  values (p_wp_year, btrim(p_name), p_minimum_increment)
  returning * into v_event;

  insert into public.audit_logs (
    actor_user_id, actor_role, action, entity_type, entity_id, after_data
  ) values (
    auth.uid(),
    'GM'::public.app_role,
    'PUBLIC_AUCTION_EVENT_CREATED',
    'public_auction_events',
    v_event.id::text,
    jsonb_build_object('wp_year', v_event.wp_year, 'name', v_event.name, 'minimum_increment', v_event.minimum_increment)
  );

  return v_event;
end;
$$;

create function public.set_public_auction_event_status(
  p_event_id uuid,
  p_status public.public_auction_event_status
)
returns public.public_auction_events
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_event public.public_auction_events%rowtype;
  v_previous_status public.public_auction_event_status;
begin
  if auth.uid() is null or not public.is_current_user_gm() then
    raise exception 'only a GM may change a public auction event status'
      using errcode = '42501';
  end if;

  select *
  into v_event
  from public.public_auction_events
  where id = p_event_id
  for update;

  if not found then
    raise exception 'public auction event does not exist'
      using errcode = 'P0001';
  end if;

  if p_status is null then
    raise exception 'public auction event status is required'
      using errcode = '23514';
  end if;

  if p_status = v_event.status then
    return v_event;
  end if;

  if not (
    (v_event.status = 'DRAFT'::public.public_auction_event_status
      and p_status = 'OPEN'::public.public_auction_event_status)
    or (v_event.status = 'OPEN'::public.public_auction_event_status
      and p_status = 'CLOSED'::public.public_auction_event_status)
    or (v_event.status = 'CLOSED'::public.public_auction_event_status
      and p_status in (
        'OPEN'::public.public_auction_event_status,
        'SETTLED'::public.public_auction_event_status
      ))
  ) then
    raise exception 'public auction event status transition from % to % is not allowed', v_event.status, p_status
      using errcode = '23514';
  end if;

  if p_status = 'SETTLED'::public.public_auction_event_status then
    if exists (
      select 1
      from public.public_auction_lots as lot
      where lot.event_id = v_event.id
        and lot.status not in (
          'SOLD'::public.public_auction_lot_status,
          'PASSED'::public.public_auction_lot_status
        )
    ) then
      raise exception 'all public auction lots must be SOLD or PASSED before the event can be SETTLED'
        using errcode = '23514';
    end if;

    if exists (
      select 1
      from public.public_auction_rollback_requests as request
      join public.public_auction_settlements as settlement
        on settlement.id = request.settlement_id
      join public.public_auction_lots as lot
        on lot.id = settlement.lot_id
      where lot.event_id = v_event.id
        and request.status = 'PENDING_CONFIRMATION'::public.public_auction_rollback_request_status
    ) then
      raise exception 'an event with a pending emergency rollback request cannot be SETTLED'
        using errcode = '23514';
    end if;
  elsif p_status = 'CLOSED'::public.public_auction_event_status then
    if exists (
      select 1
      from public.public_auction_lots as lot
      where lot.event_id = v_event.id
        and lot.status in (
          'OPEN_WAITING'::public.public_auction_lot_status,
          'BIDDING'::public.public_auction_lot_status
        )
    ) then
      raise exception 'an active Lot must be closed/settled before closing event'
        using errcode = '23514';
    end if;
  end if;

  v_previous_status := v_event.status;

  update public.public_auction_events
  set status = p_status
  where id = v_event.id
  returning * into v_event;

  insert into public.audit_logs (
    actor_user_id, actor_role, action, entity_type, entity_id, before_data, after_data
  ) values (
    auth.uid(),
    'GM'::public.app_role,
    'PUBLIC_AUCTION_EVENT_STATUS_CHANGED',
    'public_auction_events',
    v_event.id::text,
    jsonb_build_object('status', v_previous_status),
    jsonb_build_object('status', p_status)
  );

  return v_event;
end;
$$;

create function public.create_public_auction_lot(
  p_event_id uuid,
  p_horse_id uuid,
  p_lot_number integer,
  p_starting_price bigint,
  p_evaluation_value bigint
)
returns public.public_auction_lots
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_event public.public_auction_events%rowtype;
  v_lot public.public_auction_lots%rowtype;
  v_round public.public_auction_rounds%rowtype;
begin
  if auth.uid() is null or not public.is_current_user_gm() then
    raise exception 'only a GM may create a public auction lot'
      using errcode = '42501';
  end if;

  if p_lot_number is null or p_lot_number <= 0
    or p_starting_price is null or p_starting_price < 0 or p_starting_price % 100000 <> 0
    or p_evaluation_value is null or p_evaluation_value < 0 then
    raise exception 'public auction lot fields are invalid'
      using errcode = '23514';
  end if;

  select *
  into v_event
  from public.public_auction_events
  where id = p_event_id
  for update;

  if not found or v_event.status <> 'DRAFT'::public.public_auction_event_status then
    raise exception 'public auction lots may only be configured while the event is DRAFT'
      using errcode = '23514';
  end if;

  insert into public.public_auction_lots (
    event_id, horse_id, lot_number, starting_price, evaluation_value
  ) values (
    p_event_id, p_horse_id, p_lot_number, p_starting_price, p_evaluation_value
  ) returning * into v_lot;

  insert into public.public_auction_rounds (lot_id, round_number)
  values (v_lot.id, 1)
  returning * into v_round;

  update public.public_auction_lots
  set current_round_id = v_round.id
  where id = v_lot.id
  returning * into v_lot;

  insert into public.audit_logs (
    actor_user_id, actor_role, action, entity_type, entity_id, after_data
  ) values (
    auth.uid(),
    'GM'::public.app_role,
    'PUBLIC_AUCTION_LOT_CREATED',
    'public_auction_lots',
    v_lot.id::text,
    jsonb_build_object(
      'event_id', v_lot.event_id,
      'horse_id', v_lot.horse_id,
      'lot_number', v_lot.lot_number,
      'starting_price', v_lot.starting_price,
      'evaluation_value', v_lot.evaluation_value,
      'round_id', v_round.id
    )
  );

  return v_lot;
end;
$$;

create function public.upsert_public_auction_lot_review(
  p_lot_id uuid,
  p_slot smallint,
  p_stars smallint,
  p_comment text
)
returns public.public_auction_lot_reviews
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_lot public.public_auction_lots%rowtype;
  v_review public.public_auction_lot_reviews%rowtype;
begin
  if auth.uid() is null or not public.is_current_user_gm() then
    raise exception 'only a GM may write public auction reviews'
      using errcode = '42501';
  end if;

  if p_slot is null or p_slot not between 1 and 5
    or p_stars is null or p_stars not between 1 and 5
    or nullif(btrim(p_comment), '') is null then
    raise exception 'public auction review fields are invalid'
      using errcode = '23514';
  end if;

  select *
  into v_lot
  from public.public_auction_lots
  where id = p_lot_id
  for update;

  if not found or v_lot.status <> 'QUEUED'::public.public_auction_lot_status then
    raise exception 'reviews may only be edited while the lot is QUEUED'
      using errcode = '23514';
  end if;

  if v_lot.revealed_at is not null then
    raise exception 'revealed public auction reviews require a controlled correction flow'
      using errcode = '23514';
  end if;

  insert into public.public_auction_lot_reviews (lot_id, slot, stars, comment)
  values (p_lot_id, p_slot, p_stars, btrim(p_comment))
  on conflict (lot_id, slot) do update
  set stars = excluded.stars,
      comment = excluded.comment
  returning * into v_review;

  insert into public.audit_logs (
    actor_user_id, actor_role, action, entity_type, entity_id, after_data
  ) values (
    auth.uid(),
    'GM'::public.app_role,
    'PUBLIC_AUCTION_LOT_REVIEW_UPSERTED',
    'public_auction_lot_reviews',
    v_review.id::text,
    jsonb_build_object('lot_id', v_review.lot_id, 'slot', v_review.slot, 'stars', v_review.stars)
  );

  return v_review;
end;
$$;

-- Showing a Lot is deliberately separate from opening its bidding window.
-- It makes the public read surface visible, but never changes Round state or
-- starts either server-side deadline.
create function public.reveal_public_auction_lot(p_lot_id uuid)
returns public.public_auction_lots
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_lot public.public_auction_lots%rowtype;
  v_event public.public_auction_events%rowtype;
  v_round public.public_auction_rounds%rowtype;
  v_review_count integer;
  v_revealed_at timestamptz;
begin
  if auth.uid() is null or not public.is_current_user_gm() then
    raise exception 'only a GM may reveal a public auction lot'
      using errcode = '42501';
  end if;

  select *
  into v_lot
  from public.public_auction_lots
  where id = p_lot_id
  for update;

  if not found then
    raise exception 'public auction lot does not exist'
      using errcode = 'P0001';
  end if;

  if v_lot.revealed_at is not null then
    return v_lot;
  end if;

  select *
  into v_event
  from public.public_auction_events
  where id = v_lot.event_id
  for update;

  select *
  into v_round
  from public.public_auction_rounds
  where id = v_lot.current_round_id
    and lot_id = v_lot.id
  for update;

  if not found
    or v_event.status <> 'OPEN'::public.public_auction_event_status
    or v_lot.status <> 'QUEUED'::public.public_auction_lot_status
    or v_round.status <> 'QUEUED'::public.public_auction_round_status then
    raise exception 'public auction lot is not ready to reveal'
      using errcode = '23514';
  end if;

  -- The Event row is locked above. Every reveal path therefore serializes on
  -- the Event before it decides which public surface may become visible.
  if exists (
    select 1
    from public.public_auction_lots as earlier_lot
    where earlier_lot.event_id = v_lot.event_id
      and earlier_lot.lot_number < v_lot.lot_number
      and earlier_lot.status not in (
        'SOLD'::public.public_auction_lot_status,
        'PASSED'::public.public_auction_lot_status
      )
  ) then
    raise exception 'earlier public auction lots must be SOLD or PASSED before revealing this lot'
      using errcode = '23514';
  end if;

  if exists (
    select 1
    from public.public_auction_lots as revealed_lot
    where revealed_lot.event_id = v_lot.event_id
      and revealed_lot.id <> v_lot.id
      and revealed_lot.revealed_at is not null
      and revealed_lot.status not in (
        'SOLD'::public.public_auction_lot_status,
        'PASSED'::public.public_auction_lot_status
      )
  ) then
    raise exception 'another revealed public auction lot must be SOLD or PASSED first'
      using errcode = '23514';
  end if;

  select count(*)
  into v_review_count
  from public.public_auction_lot_reviews
  where lot_id = v_lot.id;

  if v_review_count <> 5 then
    raise exception 'a public auction lot requires all five review slots before revealing'
      using errcode = '23514';
  end if;

  v_revealed_at := clock_timestamp();
  update public.public_auction_lots
  set revealed_at = v_revealed_at
  where id = v_lot.id
  returning * into v_lot;

  insert into public.audit_logs (
    actor_user_id, actor_role, action, entity_type, entity_id, after_data
  ) values (
    auth.uid(),
    'GM'::public.app_role,
    'PUBLIC_AUCTION_LOT_REVEALED',
    'public_auction_lots',
    v_lot.id::text,
    jsonb_build_object('round_id', v_round.id, 'revealed_at', v_lot.revealed_at)
  );

  return v_lot;
end;
$$;

create function public.open_public_auction_lot(p_lot_id uuid)
returns public.public_auction_rounds
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_lot public.public_auction_lots%rowtype;
  v_event public.public_auction_events%rowtype;
  v_round public.public_auction_rounds%rowtype;
  v_review_count integer;
  v_horse_owner_id uuid;
  v_horse_life_stage public.horse_life_stage;
  v_now timestamptz;
begin
  if auth.uid() is null or not public.is_current_user_gm() then
    raise exception 'only a GM may open a public auction lot'
      using errcode = '42501';
  end if;

  select *
  into v_lot
  from public.public_auction_lots
  where id = p_lot_id
  for update;

  if not found then
    raise exception 'public auction lot does not exist'
      using errcode = 'P0001';
  end if;

  select *
  into v_event
  from public.public_auction_events
  where id = v_lot.event_id
  for update;

  select *
  into v_round
  from public.public_auction_rounds
  where id = v_lot.current_round_id
    and lot_id = v_lot.id
  for update;

  if not found
    or v_event.status <> 'OPEN'::public.public_auction_event_status
    or v_lot.status <> 'QUEUED'::public.public_auction_lot_status
    or v_lot.revealed_at is null
    or v_round.status <> 'QUEUED'::public.public_auction_round_status then
    raise exception 'public auction lot is not ready to open'
      using errcode = '23514';
  end if;

  select count(*)
  into v_review_count
  from public.public_auction_lot_reviews
  where lot_id = v_lot.id;

  if v_review_count <> 5 then
    raise exception 'a public auction lot requires all five review slots before opening'
      using errcode = '23514';
  end if;

  select owner_id, life_stage
  into v_horse_owner_id, v_horse_life_stage
  from public.horses
  where id = v_lot.horse_id
  for update;

  if not found
    or v_horse_owner_id is not null
    or v_horse_life_stage <> 'FOAL'::public.horse_life_stage then
    raise exception 'public auction horse is no longer eligible to open'
      using errcode = '23514';
  end if;

  v_now := clock_timestamp();
  update public.public_auction_rounds
  set status = 'OPEN_WAITING'::public.public_auction_round_status,
      opened_at = v_now,
      no_bid_deadline = v_now + interval '10 minutes',
      close_at = null,
      closed_at = null,
      current_price = null,
      current_winner_owner_id = null
  where id = v_round.id
  returning * into v_round;

  insert into public.audit_logs (
    actor_user_id, actor_role, action, entity_type, entity_id, after_data
  ) values (
    auth.uid(),
    'GM'::public.app_role,
    'PUBLIC_AUCTION_LOT_OPENED',
    'public_auction_lots',
    v_lot.id::text,
    jsonb_build_object('round_id', v_round.id, 'opened_at', v_round.opened_at, 'no_bid_deadline', v_round.no_bid_deadline)
  );

  return v_round;
end;
$$;

create function public.close_public_auction_lot(
  p_lot_id uuid,
  p_reason text default null
)
returns public.public_auction_rounds
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_lot public.public_auction_lots%rowtype;
  v_event public.public_auction_events%rowtype;
  v_round public.public_auction_rounds%rowtype;
  v_now timestamptz;
begin
  if auth.uid() is null or not public.is_current_user_gm() then
    raise exception 'only a GM may close a public auction lot'
      using errcode = '42501';
  end if;

  select *
  into v_lot
  from public.public_auction_lots
  where id = p_lot_id
  for update;

  if not found then
    raise exception 'public auction lot does not exist'
      using errcode = 'P0001';
  end if;

  select *
  into v_event
  from public.public_auction_events
  where id = v_lot.event_id
  for update;

  if not found then
    raise exception 'public auction rollback event does not exist'
      using errcode = '23503';
  end if;

  select *
  into v_round
  from public.public_auction_rounds
  where id = v_lot.current_round_id
  for update;

  if v_round.status = 'CLOSED'::public.public_auction_round_status then
    return v_round;
  end if;

  v_now := clock_timestamp();
  if v_round.status = 'OPEN_WAITING'::public.public_auction_round_status then
    null; -- GM may end a no-bid waiting Lot at any time.
  elsif v_round.status = 'BIDDING'::public.public_auction_round_status
    and v_now >= v_round.close_at then
    null;
  else
    raise exception 'a bidding public auction lot may close only after its server deadline'
      using errcode = '23514';
  end if;

  update public.public_auction_rounds
  set status = 'CLOSED'::public.public_auction_round_status,
      closed_at = v_now
  where id = v_round.id
  returning * into v_round;

  insert into public.audit_logs (
    actor_user_id, actor_role, action, entity_type, entity_id, after_data, reason
  ) values (
    auth.uid(),
    'GM'::public.app_role,
    'PUBLIC_AUCTION_LOT_CLOSED',
    'public_auction_lots',
    v_lot.id::text,
    jsonb_build_object('round_id', v_round.id, 'current_price', v_round.current_price, 'winner_owner_id', v_round.current_winner_owner_id),
    nullif(btrim(p_reason), '')
  );

  return v_round;
end;
$$;

create function public.reopen_public_auction_lot(
  p_lot_id uuid,
  p_reopen_reason text
)
returns public.public_auction_rounds
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_lot public.public_auction_lots%rowtype;
  v_event public.public_auction_events%rowtype;
  v_round public.public_auction_rounds%rowtype;
  v_now timestamptz;
begin
  if auth.uid() is null or not public.is_current_user_gm() then
    raise exception 'only a GM may reopen a public auction lot'
      using errcode = '42501';
  end if;

  if nullif(btrim(p_reopen_reason), '') is null then
    raise exception 'public auction reopen requires a non-empty reason'
      using errcode = '23514';
  end if;

  select *
  into v_lot
  from public.public_auction_lots
  where id = p_lot_id
  for update;

  if not found then
    raise exception 'public auction lot does not exist'
      using errcode = 'P0001';
  end if;

  select *
  into v_event
  from public.public_auction_events
  where id = v_lot.event_id
  for update;

  if not found then
    raise exception 'public auction event does not exist'
      using errcode = '23503';
  end if;

  if v_event.status <> 'OPEN'::public.public_auction_event_status then
    raise exception 'public auction event must be OPEN before reopening a lot'
      using errcode = '23514';
  end if;

  select *
  into v_round
  from public.public_auction_rounds
  where id = v_lot.current_round_id
  for update;

  if v_round.status <> 'CLOSED'::public.public_auction_round_status
    or exists (select 1 from public.public_auction_settlements where round_id = v_round.id) then
    raise exception 'only an unsettled CLOSED public auction lot may be reopened normally'
      using errcode = '23514';
  end if;

  v_now := clock_timestamp();
  if v_round.current_price is null then
    update public.public_auction_rounds
    set status = 'OPEN_WAITING'::public.public_auction_round_status,
        no_bid_deadline = v_now + interval '10 minutes',
        close_at = null,
        closed_at = null
    where id = v_round.id
    returning * into v_round;
  else
    update public.public_auction_rounds
    set status = 'BIDDING'::public.public_auction_round_status,
        close_at = v_now + interval '10 seconds',
        no_bid_deadline = null,
        closed_at = null
    where id = v_round.id
    returning * into v_round;
  end if;

  insert into public.audit_logs (
    actor_user_id, actor_role, action, entity_type, entity_id, before_data, after_data, reason
  ) values (
    auth.uid(),
    'GM'::public.app_role,
    'PUBLIC_AUCTION_LOT_REOPENED',
    'public_auction_lots',
    v_lot.id::text,
    jsonb_build_object('round_status', 'CLOSED', 'current_price', v_lot.current_price),
    jsonb_build_object('round_status', v_round.status, 'close_at', v_round.close_at, 'no_bid_deadline', v_round.no_bid_deadline),
    btrim(p_reopen_reason)
  );

  return v_round;
end;
$$;

-- Client bids are accepted only through this serialised entry point. A stable
-- request id makes a transport retry idempotent without ever changing the
-- already-accepted auction fact.
create function public.submit_public_auction_bid(
  p_lot_id uuid,
  p_expected_round_id uuid,
  p_amount bigint,
  p_request_id uuid
)
returns public.public_auction_bids
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner_id uuid;
  v_lot public.public_auction_lots%rowtype;
  v_round public.public_auction_rounds%rowtype;
  v_event public.public_auction_events%rowtype;
  v_bid public.public_auction_bids%rowtype;
  v_now timestamptz;
  v_account_funds bigint;
  v_secret_frozen bigint;
  v_other_public_frozen bigint;
begin
  if auth.uid() is null then
    raise exception 'an authenticated PLAYER is required to submit a public auction bid'
      using errcode = '42501';
  end if;

  select profile.owner_id
  into v_owner_id
  from public.user_profiles as profile
  where profile.id = auth.uid()
    and profile.role = 'PLAYER'::public.app_role;

  if v_owner_id is null then
    raise exception 'only a PLAYER with a valid Owner binding may submit a public auction bid'
      using errcode = '42501';
  end if;

  if p_lot_id is null
    or p_expected_round_id is null
    or p_request_id is null
    or p_amount is null
    or p_amount < 0
    or p_amount % 100000 <> 0 then
    raise exception 'public auction bid fields are invalid'
      using errcode = '23514';
  end if;

  select *
  into v_lot
  from public.public_auction_lots
  where id = p_lot_id
  for update;

  if not found then
    raise exception 'public auction lot does not exist'
      using errcode = 'P0001';
  end if;

  if v_lot.current_round_id <> p_expected_round_id then
    raise exception 'auction round has changed; stale bid request rejected'
      using errcode = '23514';
  end if;

  select *
  into v_round
  from public.public_auction_rounds
  where id = p_expected_round_id
  for update;

  if not found or v_round.lot_id <> v_lot.id then
    raise exception 'auction round has changed; stale bid request rejected'
      using errcode = '23514';
  end if;

  -- Retry detection occurs after the Lot/Round lock so it cannot return a
  -- stale request while a rollback or settlement is switching rounds.
  select *
  into v_bid
  from public.public_auction_bids
  where owner_id = v_owner_id
    and round_id = v_round.id
    and request_id = p_request_id;

  if found then
    if v_bid.amount = p_amount then
      return v_bid;
    end if;

    raise exception 'idempotency key conflict: request_id was already used with a different amount'
      using errcode = '23514';
  end if;

  select *
  into v_event
  from public.public_auction_events
  where id = v_lot.event_id
  for key share;

  if v_event.status <> 'OPEN'::public.public_auction_event_status
    or v_round.status not in (
      'OPEN_WAITING'::public.public_auction_round_status,
      'BIDDING'::public.public_auction_round_status
    ) then
    raise exception 'public auction lot is not accepting bids'
      using errcode = '23514';
  end if;

  v_now := clock_timestamp();

  if v_round.status = 'OPEN_WAITING'::public.public_auction_round_status then
    if v_round.no_bid_deadline is null or v_now >= v_round.no_bid_deadline then
      raise exception 'the no-bid deadline has passed'
        using errcode = '23514';
    end if;

    if p_amount < v_lot.starting_price then
      raise exception 'the first public auction bid must meet the starting price'
        using errcode = '23514';
    end if;
  else
    if v_round.close_at is null or v_now >= v_round.close_at then
      raise exception 'the public auction bidding clock has closed'
        using errcode = '23514';
    end if;

    if v_round.current_winner_owner_id = v_owner_id then
      raise exception 'you are already the current highest bidder'
        using errcode = '23514';
    end if;

    if p_amount < v_round.current_price + v_event.minimum_increment then
      raise exception 'the public auction bid does not meet the minimum increment'
        using errcode = '23514';
    end if;
  end if;

  -- This lock is the common serialisation point with foal-trade offer writes
  -- and public-auction settlement. All frozen sources are checked in one
  -- transaction before the new winning amount is made visible.
  perform 1
  from public.owners
  where id = v_owner_id
  for update;

  select owner.initial_funds + coalesce(sum(transaction_row.amount), 0)
  into v_account_funds
  from public.owners as owner
  left join public.financial_transactions as transaction_row
    on transaction_row.owner_id = owner.id
  where owner.id = v_owner_id
  group by owner.id, owner.initial_funds;

  select coalesce(sum(offer.amount), 0)
  into v_secret_frozen
  from public.secret_bid_offers as offer
  where offer.owner_id = v_owner_id
    and offer.status = 'ACTIVE'::public.secret_bid_offer_status;

  select coalesce(sum(other_round.current_price), 0)
  into v_other_public_frozen
  from public.public_auction_rounds as other_round
  join public.public_auction_lots as other_lot
    on other_lot.current_round_id = other_round.id
  where other_round.current_winner_owner_id = v_owner_id
    and other_round.id <> v_round.id
    and other_round.status in (
      'BIDDING'::public.public_auction_round_status,
      'CLOSED'::public.public_auction_round_status
    );

  if v_account_funds - v_secret_frozen - v_other_public_frozen - p_amount < 0 then
    raise exception 'public auction bid would exceed available funds'
      using errcode = 'P0001';
  end if;

  insert into public.public_auction_bids (
    lot_id, round_id, owner_id, amount, request_id, accepted_at
  ) values (
    v_lot.id, v_round.id, v_owner_id, p_amount, p_request_id, v_now
  ) returning * into v_bid;

  update public.public_auction_rounds
  set status = 'BIDDING'::public.public_auction_round_status,
      current_price = p_amount,
      current_winner_owner_id = v_owner_id,
      close_at = v_bid.accepted_at + interval '10 seconds',
      no_bid_deadline = null,
      closed_at = null
  where id = v_round.id;

  return v_bid;
end;
$$;

create function public.get_current_owner_financial_summary()
returns table (
  account_funds bigint,
  foal_trade_frozen_funds bigint,
  public_auction_frozen_funds bigint,
  total_frozen_funds bigint,
  available_funds bigint
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_owner_id uuid;
begin
  if auth.uid() is null then
    raise exception 'an authenticated PLAYER is required to read Owner financial summary'
      using errcode = '42501';
  end if;

  select profile.owner_id
  into v_owner_id
  from public.user_profiles as profile
  where profile.id = auth.uid()
    and profile.role = 'PLAYER'::public.app_role;

  if v_owner_id is null then
    raise exception 'only a PLAYER with a valid Owner binding may read Owner financial summary'
      using errcode = '42501';
  end if;

  return query
  select
    owner.initial_funds + ledger.transaction_total as account_funds,
    secret_frozen.active_offer_total as foal_trade_frozen_funds,
    auction_frozen.current_winner_total as public_auction_frozen_funds,
    secret_frozen.active_offer_total + auction_frozen.current_winner_total as total_frozen_funds,
    owner.initial_funds + ledger.transaction_total
      - secret_frozen.active_offer_total
      - auction_frozen.current_winner_total as available_funds
  from public.owners as owner
  cross join lateral (
    select coalesce(sum(transaction_row.amount), 0)::bigint as transaction_total
    from public.financial_transactions as transaction_row
    where transaction_row.owner_id = owner.id
  ) as ledger
  cross join lateral (
    select coalesce(sum(offer.amount), 0)::bigint as active_offer_total
    from public.secret_bid_offers as offer
    where offer.owner_id = owner.id
      and offer.status = 'ACTIVE'::public.secret_bid_offer_status
  ) as secret_frozen
  cross join lateral (
    select coalesce(sum(round_row.current_price), 0)::bigint as current_winner_total
    from public.public_auction_rounds as round_row
    join public.public_auction_lots as lot
      on lot.current_round_id = round_row.id
    where round_row.current_winner_owner_id = owner.id
      and round_row.status in (
        'BIDDING'::public.public_auction_round_status,
        'CLOSED'::public.public_auction_round_status
      )
  ) as auction_frozen
  where owner.id = v_owner_id;

  if not found then
    raise exception 'PLAYER Owner binding is invalid'
      using errcode = '23503';
  end if;
end;
$$;

-- Uses database time to materialise an elapsed auction clock only when a GM
-- acts on the Round. No client clock can decide whether a result is valid.
create function public.close_public_auction_round_if_elapsed(
  p_round_id uuid
)
returns public.public_auction_rounds
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_round public.public_auction_rounds%rowtype;
  v_now timestamptz := clock_timestamp();
begin
  select *
  into v_round
  from public.public_auction_rounds
  where id = p_round_id
  for update;

  if not found then
    raise exception 'public auction round does not exist'
      using errcode = 'P0001';
  end if;

  if (v_round.status = 'BIDDING'::public.public_auction_round_status
      and v_round.close_at is not null
      and v_now >= v_round.close_at)
    or (v_round.status = 'OPEN_WAITING'::public.public_auction_round_status
      and v_round.no_bid_deadline is not null
      and v_now >= v_round.no_bid_deadline) then
    update public.public_auction_rounds
    set status = 'CLOSED'::public.public_auction_round_status,
        closed_at = v_now
    where id = v_round.id
    returning * into v_round;
  end if;

  return v_round;
end;
$$;

create function public.settle_public_auction_lot(
  p_lot_id uuid,
  p_reason text default null
)
returns public.public_auction_settlements
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_lot public.public_auction_lots%rowtype;
  v_round public.public_auction_rounds%rowtype;
  v_settlement public.public_auction_settlements%rowtype;
  v_horse public.horses%rowtype;
  v_account_funds bigint;
  v_secret_frozen bigint;
  v_other_public_frozen bigint;
  v_transaction_id uuid;
begin
  if auth.uid() is null or not public.is_current_user_gm() then
    raise exception 'only a GM may settle a public auction sale'
      using errcode = '42501';
  end if;

  select *
  into v_lot
  from public.public_auction_lots
  where id = p_lot_id
  for update;

  if not found then
    raise exception 'public auction lot does not exist'
      using errcode = 'P0001';
  end if;

  select *
  into v_round
  from public.public_auction_rounds
  where id = v_lot.current_round_id
  for update;

  select *
  into v_settlement
  from public.public_auction_settlements
  where round_id = v_round.id
  for update;

  if found then
    return v_settlement;
  end if;

  v_round := public.close_public_auction_round_if_elapsed(v_round.id);

  if v_round.status <> 'CLOSED'::public.public_auction_round_status
    or v_round.current_winner_owner_id is null
    or v_round.current_price is null then
    raise exception 'only a CLOSED public auction round with a winner may be sold'
      using errcode = '23514';
  end if;

  select *
  into v_horse
  from public.horses
  where id = v_lot.horse_id
  for update;

  if v_horse.owner_id is not null
    or v_horse.life_stage <> 'FOAL'::public.horse_life_stage then
    raise exception 'public auction sale requires an unowned FOAL Horse'
      using errcode = '23514';
  end if;

  perform 1
  from public.owners
  where id = v_round.current_winner_owner_id
  for update;

  select owner.initial_funds + coalesce(sum(transaction_row.amount), 0)
  into v_account_funds
  from public.owners as owner
  left join public.financial_transactions as transaction_row
    on transaction_row.owner_id = owner.id
  where owner.id = v_round.current_winner_owner_id
  group by owner.id, owner.initial_funds;

  select coalesce(sum(offer.amount), 0)
  into v_secret_frozen
  from public.secret_bid_offers as offer
  where offer.owner_id = v_round.current_winner_owner_id
    and offer.status = 'ACTIVE'::public.secret_bid_offer_status;

  select coalesce(sum(other_round.current_price), 0)
  into v_other_public_frozen
  from public.public_auction_rounds as other_round
  join public.public_auction_lots as other_lot
    on other_lot.current_round_id = other_round.id
  where other_round.current_winner_owner_id = v_round.current_winner_owner_id
    and other_round.id <> v_round.id
    and other_round.status in (
      'BIDDING'::public.public_auction_round_status,
      'CLOSED'::public.public_auction_round_status
    );

  if v_account_funds - v_secret_frozen - v_other_public_frozen - v_round.current_price < 0 then
    raise exception 'public auction sale would leave the winning Owner with negative available funds'
      using errcode = 'P0001';
  end if;

  insert into public.public_auction_settlements (
    lot_id, round_id, horse_id, status, winner_owner_id, amount,
    confirmed_by_user_id, reason
  ) values (
    v_lot.id, v_round.id, v_horse.id,
    'SOLD'::public.public_auction_settlement_status,
    v_round.current_winner_owner_id, v_round.current_price,
    auth.uid(), nullif(btrim(p_reason), '')
  ) returning * into v_settlement;

  insert into public.financial_transactions (
    owner_id, amount, transaction_kind, source_entity_type, source_entity_id,
    created_by_user_id, reason
  ) values (
    v_round.current_winner_owner_id,
    -v_round.current_price,
    'PUBLIC_AUCTION_PURCHASE',
    'PUBLIC_AUCTION_SETTLEMENT',
    v_settlement.id,
    auth.uid(),
    coalesce(nullif(btrim(p_reason), ''), 'Public auction Lot ' || v_lot.lot_number::text || ' purchase')
  ) returning id into v_transaction_id;

  perform set_config('horserpg.public_auction_settlement', v_settlement.id::text, true);

  update public.horses
  set owner_id = v_round.current_winner_owner_id,
      life_stage = 'OWNED_FOAL'::public.horse_life_stage
  where id = v_horse.id;

  update public.public_auction_rounds
  set status = 'SOLD'::public.public_auction_round_status,
      closed_at = coalesce(closed_at, clock_timestamp())
  where id = v_round.id;

  insert into public.audit_logs (
    actor_user_id, actor_role, action, entity_type, entity_id, after_data, reason
  ) values (
    auth.uid(),
    'GM'::public.app_role,
    'PUBLIC_AUCTION_LOT_SOLD',
    'public_auction_settlements',
    v_settlement.id::text,
    jsonb_build_object(
      'lot_id', v_lot.id,
      'round_id', v_round.id,
      'horse_id', v_horse.id,
      'winner_owner_id', v_round.current_winner_owner_id,
      'amount', v_round.current_price,
      'financial_transaction_id', v_transaction_id
    ),
    nullif(btrim(p_reason), '')
  );

  return v_settlement;
end;
$$;

create function public.settle_public_auction_pass(
  p_lot_id uuid,
  p_reason text default null
)
returns public.public_auction_settlements
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_lot public.public_auction_lots%rowtype;
  v_round public.public_auction_rounds%rowtype;
  v_settlement public.public_auction_settlements%rowtype;
  v_horse public.horses%rowtype;
begin
  if auth.uid() is null or not public.is_current_user_gm() then
    raise exception 'only a GM may settle a public auction pass'
      using errcode = '42501';
  end if;

  select *
  into v_lot
  from public.public_auction_lots
  where id = p_lot_id
  for update;

  if not found then
    raise exception 'public auction lot does not exist'
      using errcode = 'P0001';
  end if;

  select *
  into v_round
  from public.public_auction_rounds
  where id = v_lot.current_round_id
  for update;

  select *
  into v_settlement
  from public.public_auction_settlements
  where round_id = v_round.id
  for update;

  if found then
    return v_settlement;
  end if;

  v_round := public.close_public_auction_round_if_elapsed(v_round.id);

  if v_round.status <> 'CLOSED'::public.public_auction_round_status
    or v_round.current_winner_owner_id is not null
    or v_round.current_price is not null then
    raise exception 'only a CLOSED public auction round without a winner may be passed'
      using errcode = '23514';
  end if;

  select *
  into v_horse
  from public.horses
  where id = v_lot.horse_id
  for update;

  if v_horse.owner_id is not null
    or v_horse.life_stage <> 'FOAL'::public.horse_life_stage then
    raise exception 'public auction pass requires an unowned FOAL Horse'
      using errcode = '23514';
  end if;

  insert into public.public_auction_settlements (
    lot_id, round_id, horse_id, status, confirmed_by_user_id, reason
  ) values (
    v_lot.id, v_round.id, v_horse.id,
    'PASSED'::public.public_auction_settlement_status,
    auth.uid(), nullif(btrim(p_reason), '')
  ) returning * into v_settlement;

  perform set_config('horserpg.public_auction_pass', v_settlement.id::text, true);

  update public.horses
  set life_stage = 'DISCARDED'::public.horse_life_stage
  where id = v_horse.id;

  update public.public_auction_rounds
  set status = 'PASSED'::public.public_auction_round_status,
      closed_at = coalesce(closed_at, clock_timestamp())
  where id = v_round.id;

  insert into public.audit_logs (
    actor_user_id, actor_role, action, entity_type, entity_id, after_data, reason
  ) values (
    auth.uid(),
    'GM'::public.app_role,
    'PUBLIC_AUCTION_LOT_PASSED',
    'public_auction_settlements',
    v_settlement.id::text,
    jsonb_build_object('lot_id', v_lot.id, 'round_id', v_round.id, 'horse_id', v_horse.id),
    nullif(btrim(p_reason), '')
  );

  return v_settlement;
end;
$$;

create function public.request_public_auction_emergency_rollback(
  p_lot_id uuid,
  p_reason text
)
returns public.public_auction_rollback_requests
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_lot public.public_auction_lots%rowtype;
  v_event public.public_auction_events%rowtype;
  v_round public.public_auction_rounds%rowtype;
  v_settlement public.public_auction_settlements%rowtype;
  v_request public.public_auction_rollback_requests%rowtype;
begin
  if auth.uid() is null or not public.is_current_user_gm() then
    raise exception 'only a GM may request a public auction emergency rollback'
      using errcode = '42501';
  end if;

  if nullif(btrim(p_reason), '') is null then
    raise exception 'public auction emergency rollback requires a non-empty reason'
      using errcode = '23514';
  end if;

  select *
  into v_lot
  from public.public_auction_lots
  where id = p_lot_id
  for update;

  if not found then
    raise exception 'public auction lot does not exist'
      using errcode = 'P0001';
  end if;

  select *
  into v_event
  from public.public_auction_events
  where id = v_lot.event_id
  for update;

  if not found then
    raise exception 'public auction rollback event does not exist'
      using errcode = '23503';
  end if;

  select *
  into v_round
  from public.public_auction_rounds
  where id = v_lot.current_round_id
  for update;

  select *
  into v_settlement
  from public.public_auction_settlements
  where round_id = v_round.id
  for update;

  if not found
    or v_round.status not in (
      'SOLD'::public.public_auction_round_status,
      'PASSED'::public.public_auction_round_status
    )
    or v_settlement.rolled_back_at is not null then
    raise exception 'only a final, unrolled-back public auction result may enter emergency rollback'
      using errcode = '23514';
  end if;

  select *
  into v_request
  from public.public_auction_rollback_requests
  where settlement_id = v_settlement.id
    and status = 'PENDING_CONFIRMATION'::public.public_auction_rollback_request_status
  for update;

  if found then
    return v_request;
  end if;

  insert into public.public_auction_rollback_requests (
    lot_id, round_id, settlement_id, requested_by_user_id, reason, expected_confirmation
  ) values (
    v_lot.id,
    v_round.id,
    v_settlement.id,
    auth.uid(),
    btrim(p_reason),
    'ROLLBACK LOT ' || lpad(v_lot.lot_number::text, 3, '0')
  ) returning * into v_request;

  insert into public.audit_logs (
    actor_user_id, actor_role, action, entity_type, entity_id, after_data, reason
  ) values (
    auth.uid(),
    'GM'::public.app_role,
    'PUBLIC_AUCTION_EMERGENCY_ROLLBACK_REQUESTED',
    'public_auction_rollback_requests',
    v_request.id::text,
    jsonb_build_object(
      'lot_id', v_lot.id,
      'round_id', v_round.id,
      'settlement_id', v_settlement.id,
      'settlement_status', v_settlement.status,
      'expected_confirmation', v_request.expected_confirmation
    ),
    v_request.reason
  );

  return v_request;
end;
$$;

create function public.confirm_public_auction_emergency_rollback(
  p_rollback_request_id uuid,
  p_confirmation text
)
returns public.public_auction_rollback_requests
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_request public.public_auction_rollback_requests%rowtype;
  v_request_snapshot public.public_auction_rollback_requests%rowtype;
  v_event public.public_auction_events%rowtype;
  v_lot public.public_auction_lots%rowtype;
  v_round public.public_auction_rounds%rowtype;
  v_settlement public.public_auction_settlements%rowtype;
  v_horse public.horses%rowtype;
  v_new_round public.public_auction_rounds%rowtype;
  v_compensation_transaction_id uuid;
  v_next_round_number integer;
  v_original_purchase_count integer;
  v_now timestamptz;
begin
  if auth.uid() is null or not public.is_current_user_gm() then
    raise exception 'only a GM may confirm a public auction emergency rollback'
      using errcode = '42501';
  end if;

  -- Read only the immutable locator first. It deliberately does not lock the
  -- Request; all competing request/confirm paths then lock in the common
  -- Lot -> Event -> Round -> Settlement -> Request order below.
  select *
  into v_request_snapshot
  from public.public_auction_rollback_requests
  where id = p_rollback_request_id;

  if not found then
    raise exception 'public auction rollback request does not exist'
      using errcode = 'P0001';
  end if;

  select *
  into v_lot
  from public.public_auction_lots
  where id = v_request_snapshot.lot_id
  for update;

  if not found then
    raise exception 'public auction rollback request Lot does not exist'
      using errcode = '23503';
  end if;

  select *
  into v_event
  from public.public_auction_events
  where id = v_lot.event_id
  for update;

  if not found then
    raise exception 'public auction rollback event does not exist'
      using errcode = '23503';
  end if;

  select *
  into v_round
  from public.public_auction_rounds
  where id = v_request_snapshot.round_id
  for update;

  if not found then
    raise exception 'public auction rollback request Round does not exist'
      using errcode = '23503';
  end if;

  select *
  into v_settlement
  from public.public_auction_settlements
  where id = v_request_snapshot.settlement_id
  for update;

  if not found then
    raise exception 'public auction rollback request Settlement does not exist'
      using errcode = '23503';
  end if;

  select *
  into v_request
  from public.public_auction_rollback_requests
  where id = p_rollback_request_id
  for update;

  if not found then
    raise exception 'public auction rollback request does not exist'
      using errcode = 'P0001';
  end if;

  if v_request.status = 'EXECUTED'::public.public_auction_rollback_request_status then
    return v_request;
  end if;

  if v_request.status <> 'PENDING_CONFIRMATION'::public.public_auction_rollback_request_status
    or v_request.lot_id <> v_lot.id
    or v_request.round_id <> v_round.id
    or v_request.settlement_id <> v_settlement.id
    or nullif(btrim(p_confirmation), '') is distinct from v_request.expected_confirmation then
    raise exception 'public auction emergency rollback confirmation is invalid'
      using errcode = '23514';
  end if;

  if v_lot.current_round_id <> v_round.id
    or v_round.lot_id <> v_lot.id
    or v_settlement.lot_id <> v_lot.id
    or v_settlement.round_id <> v_round.id
    or v_settlement.rolled_back_at is not null
    or v_round.status not in (
      'SOLD'::public.public_auction_round_status,
      'PASSED'::public.public_auction_round_status
    ) then
    raise exception 'public auction rollback request no longer matches the final lot result'
      using errcode = '23514';
  end if;

  -- A rollback makes this Lot unfinished again. Do not let that create two
  -- concurrently revealed, unfinished Lots in the same Event.
  if exists (
    select 1
    from public.public_auction_lots as other_lot
    where other_lot.event_id = v_event.id
      and other_lot.id <> v_lot.id
      and other_lot.revealed_at is not null
      and other_lot.status not in (
        'SOLD'::public.public_auction_lot_status,
        'PASSED'::public.public_auction_lot_status
      )
  ) then
    raise exception 'cannot rollback while another revealed public auction lot is unfinished'
      using errcode = '23514';
  end if;

  v_now := clock_timestamp();

  select *
  into v_horse
  from public.horses
  where id = v_settlement.horse_id
  for update;

  if v_settlement.status = 'SOLD'::public.public_auction_settlement_status then
    if v_horse.owner_id is distinct from v_settlement.winner_owner_id
      or v_horse.life_stage <> 'OWNED_FOAL'::public.horse_life_stage then
      raise exception 'sold public auction rollback requires the Horse to retain its settlement Owner'
        using errcode = '23514';
    end if;

    perform 1
    from public.owners
    where id = v_settlement.winner_owner_id
    for update;

    select count(*)
    into v_original_purchase_count
    from public.financial_transactions
    where owner_id = v_settlement.winner_owner_id
      and amount = -v_settlement.amount
      and source_entity_type = 'PUBLIC_AUCTION_SETTLEMENT'
      and source_entity_id = v_settlement.id;

    if v_original_purchase_count <> 1 then
      raise exception 'sold public auction rollback requires exactly one matching original purchase ledger entry'
        using errcode = '23514';
    end if;
  elsif v_settlement.status = 'PASSED'::public.public_auction_settlement_status then
    if v_horse.owner_id is not null
      or v_horse.life_stage <> 'DISCARDED'::public.horse_life_stage then
      raise exception 'passed public auction rollback requires the Horse to remain unowned and DISCARDED'
        using errcode = '23514';
    end if;
  else
    raise exception 'public auction rollback result status is invalid'
      using errcode = '23514';
  end if;

  update public.public_auction_settlements
  set rolled_back_at = v_now,
      rolled_back_by_user_id = auth.uid(),
      rollback_request_id = v_request.id
  where id = v_settlement.id;

  perform set_config('horserpg.public_auction_rollback', v_settlement.id::text, true);

  if v_settlement.status = 'SOLD'::public.public_auction_settlement_status then
    insert into public.financial_transactions (
      owner_id, amount, transaction_kind, source_entity_type, source_entity_id,
      created_by_user_id, reason
    ) values (
      v_settlement.winner_owner_id,
      v_settlement.amount,
      'PUBLIC_AUCTION_ROLLBACK',
      'PUBLIC_AUCTION_ROLLBACK',
      v_request.id,
      auth.uid(),
      'Emergency rollback compensation for public auction Lot ' || v_lot.lot_number::text
    ) returning id into v_compensation_transaction_id;

    update public.horses
    set owner_id = null,
        life_stage = 'FOAL'::public.horse_life_stage
    where id = v_horse.id;
  else
    update public.horses
    set life_stage = 'FOAL'::public.horse_life_stage
    where id = v_horse.id;
  end if;

  select coalesce(max(round_number), 0) + 1
  into v_next_round_number
  from public.public_auction_rounds
  where lot_id = v_lot.id;

  insert into public.public_auction_rounds (lot_id, round_number)
  values (v_lot.id, v_next_round_number)
  returning * into v_new_round;

  -- Switch the live pointer before voiding the historical round, so the Lot
  -- is always represented by a current Round and no old bid can freeze funds.
  update public.public_auction_lots
  set current_round_id = v_new_round.id
  where id = v_lot.id;

  if v_event.status in (
    'CLOSED'::public.public_auction_event_status,
    'SETTLED'::public.public_auction_event_status
  ) then
    update public.public_auction_events
    set status = 'OPEN'::public.public_auction_event_status
    where id = v_event.id;

    insert into public.audit_logs (
      actor_user_id, actor_role, action, entity_type, entity_id, before_data, after_data, reason
    ) values (
      auth.uid(),
      'GM'::public.app_role,
      'PUBLIC_AUCTION_EVENT_REOPENED_BY_EMERGENCY_ROLLBACK',
      'public_auction_events',
      v_event.id::text,
      jsonb_build_object('status', v_event.status),
      jsonb_build_object(
        'status', 'OPEN',
        'lot_id', v_lot.id,
        'rollback_request_id', v_request.id,
        'new_round_id', v_new_round.id
      ),
      v_request.reason
    );
  end if;

  update public.public_auction_rounds
  set status = 'VOIDED'::public.public_auction_round_status
  where id = v_round.id;

  update public.public_auction_rollback_requests
  set status = 'EXECUTED'::public.public_auction_rollback_request_status,
      confirmed_by_user_id = auth.uid(),
      confirmed_at = v_now,
      executed_at = v_now,
      compensation_transaction_id = v_compensation_transaction_id,
      new_round_id = v_new_round.id
  where id = v_request.id
  returning * into v_request;

  insert into public.audit_logs (
    actor_user_id, actor_role, action, entity_type, entity_id, before_data, after_data, reason
  ) values (
    auth.uid(),
    'GM'::public.app_role,
    'PUBLIC_AUCTION_EMERGENCY_ROLLBACK_EXECUTED',
    'public_auction_rollback_requests',
    v_request.id::text,
    jsonb_build_object(
      'lot_id', v_lot.id,
      'round_id', v_round.id,
      'settlement_id', v_settlement.id,
      'status', v_settlement.status,
      'winner_owner_id', v_settlement.winner_owner_id,
      'amount', v_settlement.amount
    ),
    jsonb_build_object(
      'new_round_id', v_new_round.id,
      'compensation_transaction_id', v_compensation_transaction_id
    ),
    v_request.reason
  );

  return v_request;
end;
$$;

-- Settlements are intentionally not readable directly by PLAYERs. This view
-- is the narrow, post-settlement public result surface and excludes rollback
-- reasons, internal request details, and historical voided outcomes.
create view public.public_auction_public_settlements
with (security_barrier = true)
as
select
  settlement.lot_id,
  lot.event_id,
  settlement.horse_id,
  settlement.status,
  settlement.winner_owner_id,
  settlement.amount,
  settlement.confirmed_at
from public.public_auction_settlements as settlement
join public.public_auction_lots as lot
  on lot.id = settlement.lot_id
where settlement.rolled_back_at is null;

alter table public.public_auction_events enable row level security;
alter table public.public_auction_lots enable row level security;
alter table public.public_auction_rounds enable row level security;
alter table public.public_auction_lot_reviews enable row level security;
alter table public.public_auction_bids enable row level security;
alter table public.public_auction_settlements enable row level security;
alter table public.public_auction_rollback_requests enable row level security;

create policy public_auction_events_read_authenticated
on public.public_auction_events
for select to authenticated
using (true);

create policy public_auction_lots_read_authenticated
on public.public_auction_lots
for select to authenticated
using (
  public.is_current_user_gm()
  or revealed_at is not null
);

create policy public_auction_lot_reviews_read_authenticated
on public.public_auction_lot_reviews
for select to authenticated
using (
  public.is_current_user_gm()
  or exists (
    select 1
    from public.public_auction_lots as lot
    where lot.id = public_auction_lot_reviews.lot_id
      and lot.revealed_at is not null
  )
);

create policy public_auction_rounds_read_current_or_gm
on public.public_auction_rounds
for select to authenticated
using (
  public.is_current_user_gm()
  or exists (
    select 1
    from public.public_auction_lots as lot
    where lot.current_round_id = public_auction_rounds.id
      and lot.revealed_at is not null
  )
);

create policy public_auction_bids_read_current_round_or_gm
on public.public_auction_bids
for select to authenticated
using (
  public.is_current_user_gm()
  or exists (
    select 1
    from public.public_auction_lots as lot
    where lot.current_round_id = public_auction_bids.round_id
      and lot.revealed_at is not null
  )
);

create policy public_auction_settlements_read_gm
on public.public_auction_settlements
for select to authenticated
using (public.is_current_user_gm());

create policy public_auction_rollback_requests_read_gm
on public.public_auction_rollback_requests
for select to authenticated
using (public.is_current_user_gm());

revoke all on table public.public_auction_events from public, anon, authenticated, service_role;
revoke all on table public.public_auction_lots from public, anon, authenticated, service_role;
revoke all on table public.public_auction_rounds from public, anon, authenticated, service_role;
revoke all on table public.public_auction_lot_reviews from public, anon, authenticated, service_role;
revoke all on table public.public_auction_bids from public, anon, authenticated, service_role;
revoke all on table public.public_auction_settlements from public, anon, authenticated, service_role;
revoke all on table public.public_auction_rollback_requests from public, anon, authenticated, service_role;

grant select on table public.public_auction_events to authenticated;
grant select on table public.public_auction_lots to authenticated;
grant select on table public.public_auction_rounds to authenticated;
grant select on table public.public_auction_lot_reviews to authenticated;
grant select on table public.public_auction_bids to authenticated;
grant select on table public.public_auction_settlements to authenticated;
grant select on table public.public_auction_rollback_requests to authenticated;

revoke all on table public.public_auction_public_settlements from public, anon, authenticated, service_role;
grant select on table public.public_auction_public_settlements to authenticated;

-- Every callable API has an explicit ACL. The GM wrappers are available to
-- authenticated users only because each verifies GM identity with auth.uid()
-- and is_current_user_gm(); helpers and trigger functions have no client ACL.
revoke all on function public.create_public_auction_event(integer, text, bigint) from public, anon, authenticated, service_role;
revoke all on function public.set_public_auction_event_status(uuid, public.public_auction_event_status) from public, anon, authenticated, service_role;
revoke all on function public.create_public_auction_lot(uuid, uuid, integer, bigint, bigint) from public, anon, authenticated, service_role;
revoke all on function public.upsert_public_auction_lot_review(uuid, smallint, smallint, text) from public, anon, authenticated, service_role;
revoke all on function public.reveal_public_auction_lot(uuid) from public, anon, authenticated, service_role;
revoke all on function public.open_public_auction_lot(uuid) from public, anon, authenticated, service_role;
revoke all on function public.close_public_auction_lot(uuid, text) from public, anon, authenticated, service_role;
revoke all on function public.reopen_public_auction_lot(uuid, text) from public, anon, authenticated, service_role;
revoke all on function public.submit_public_auction_bid(uuid, uuid, bigint, uuid) from public, anon, authenticated, service_role;
revoke all on function public.get_current_owner_financial_summary() from public, anon, authenticated, service_role;
revoke all on function public.settle_public_auction_lot(uuid, text) from public, anon, authenticated, service_role;
revoke all on function public.settle_public_auction_pass(uuid, text) from public, anon, authenticated, service_role;
revoke all on function public.request_public_auction_emergency_rollback(uuid, text) from public, anon, authenticated, service_role;
revoke all on function public.confirm_public_auction_emergency_rollback(uuid, text) from public, anon, authenticated, service_role;
revoke all on function public.close_public_auction_round_if_elapsed(uuid) from public, anon, authenticated, service_role;
revoke all on function public.enforce_public_auction_lot_horse_eligibility() from public, anon, authenticated, service_role;
revoke all on function public.enforce_public_auction_current_round_integrity() from public, anon, authenticated, service_role;
revoke all on function public.apply_public_auction_round_state_to_lot(uuid) from public, anon, authenticated, service_role;
revoke all on function public.sync_public_auction_lot_after_round_change() from public, anon, authenticated, service_role;
revoke all on function public.sync_public_auction_lot_after_current_round_change() from public, anon, authenticated, service_role;
revoke all on function public.enforce_public_auction_bid_integrity() from public, anon, authenticated, service_role;
revoke all on function public.prevent_public_auction_bid_mutation() from public, anon, authenticated, service_role;
revoke all on function public.enforce_public_auction_settlement_integrity() from public, anon, authenticated, service_role;
revoke all on function public.enforce_public_auction_rollback_request_integrity() from public, anon, authenticated, service_role;
revoke all on function public.enforce_secret_bid_offer_combined_freeze() from public, anon, authenticated, service_role;
revoke all on function public.enforce_public_auction_horse_lifecycle() from public, anon, authenticated, service_role;
revoke all on function public.prevent_horse_owner_reassignment() from public, anon, authenticated, service_role;
revoke all on function public.prevent_foal_trade_lot_horse_direct_assignment() from public, anon, authenticated, service_role;

grant execute on function public.create_public_auction_event(integer, text, bigint) to authenticated;
grant execute on function public.set_public_auction_event_status(uuid, public.public_auction_event_status) to authenticated;
grant execute on function public.create_public_auction_lot(uuid, uuid, integer, bigint, bigint) to authenticated;
grant execute on function public.upsert_public_auction_lot_review(uuid, smallint, smallint, text) to authenticated;
grant execute on function public.reveal_public_auction_lot(uuid) to authenticated;
grant execute on function public.open_public_auction_lot(uuid) to authenticated;
grant execute on function public.close_public_auction_lot(uuid, text) to authenticated;
grant execute on function public.reopen_public_auction_lot(uuid, text) to authenticated;
grant execute on function public.submit_public_auction_bid(uuid, uuid, bigint, uuid) to authenticated;
grant execute on function public.get_current_owner_financial_summary() to authenticated;
grant execute on function public.settle_public_auction_lot(uuid, text) to authenticated;
grant execute on function public.settle_public_auction_pass(uuid, text) to authenticated;
grant execute on function public.request_public_auction_emergency_rollback(uuid, text) to authenticated;
grant execute on function public.confirm_public_auction_emergency_rollback(uuid, text) to authenticated;

comment on function public.get_current_owner_financial_summary() is
  'Authenticated PLAYER-only funds summary with foal-trade and public-auction frozen funds.';

comment on view public.public_auction_public_settlements is
  'Authenticated public final public-auction results; rolled-back results and high-risk rollback details are excluded.';

commit;
