-- HorseRPG v0.2 August foal-trade database layer.
-- This migration intentionally excludes UI, public auctions, races, and remote actions.

begin;

create type public.foal_trade_session_status as enum (
  'DRAFT',
  'OPEN',
  'CLOSED',
  'REVIEWING',
  'SETTLED'
);

create type public.foal_trade_lot_status as enum ('LISTED', 'SOLD', 'UNSOLD');

create type public.foal_trade_inquiry_status as enum ('REQUESTED', 'ANSWERED');

create type public.secret_bid_offer_status as enum ('ACTIVE', 'WITHDRAWN', 'WON', 'LOST');

create type public.secret_bid_offer_history_event as enum (
  'CREATED',
  'MODIFIED',
  'REACTIVATED',
  'WITHDRAWN',
  'WON',
  'LOST'
);

create type public.foal_trade_settlement_status as enum ('SOLD', 'UNSOLD');

create table public.foal_trade_sessions (
  id uuid primary key default gen_random_uuid(),
  wp_year integer not null unique check (wp_year > 0),
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  status public.foal_trade_session_status not null default 'DRAFT'::public.foal_trade_session_status,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint foal_trade_sessions_time_order_check check (ends_at > starts_at)
);

create table public.foal_trade_lots (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references public.foal_trade_sessions(id) on delete restrict,
  horse_id uuid not null unique references public.horses(id) on delete restrict,
  minimum_price bigint not null check (minimum_price >= 0),
  status public.foal_trade_lot_status not null default 'LISTED'::public.foal_trade_lot_status,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index foal_trade_lots_session_id_idx on public.foal_trade_lots (session_id);

create table public.foal_trade_inquiries (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references public.foal_trade_sessions(id) on delete restrict,
  lot_id uuid not null references public.foal_trade_lots(id) on delete restrict,
  owner_id uuid not null references public.owners(id) on delete restrict,
  gm_comment text,
  requested_at timestamptz not null default clock_timestamp(),
  answered_at timestamptz,
  status public.foal_trade_inquiry_status not null default 'REQUESTED'::public.foal_trade_inquiry_status,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint foal_trade_inquiries_one_per_owner_per_session unique (session_id, owner_id)
);

create index foal_trade_inquiries_lot_id_idx on public.foal_trade_inquiries (lot_id);
create index foal_trade_inquiries_owner_id_idx on public.foal_trade_inquiries (owner_id);

-- One row is the current offer for an Owner/Lot pair. The immutable history
-- table below records every current-offer transition.
create table public.secret_bid_offers (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references public.foal_trade_sessions(id) on delete restrict,
  lot_id uuid not null references public.foal_trade_lots(id) on delete restrict,
  owner_id uuid not null references public.owners(id) on delete restrict,
  amount bigint not null check (amount >= 0),
  status public.secret_bid_offer_status not null default 'ACTIVE'::public.secret_bid_offer_status,
  priority_at timestamptz not null default clock_timestamp(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint secret_bid_offers_one_current_offer_per_owner_lot unique (lot_id, owner_id)
);

create index secret_bid_offers_active_owner_idx
  on public.secret_bid_offers (owner_id)
  where status = 'ACTIVE'::public.secret_bid_offer_status;

create index secret_bid_offers_active_lot_winner_idx
  on public.secret_bid_offers (lot_id, amount desc, priority_at asc, id asc)
  where status = 'ACTIVE'::public.secret_bid_offer_status;

create table public.secret_bid_offer_history (
  id uuid primary key default gen_random_uuid(),
  offer_id uuid not null references public.secret_bid_offers(id) on delete restrict,
  lot_id uuid not null references public.foal_trade_lots(id) on delete restrict,
  owner_id uuid not null references public.owners(id) on delete restrict,
  event_type public.secret_bid_offer_history_event not null,
  amount bigint not null check (amount >= 0),
  priority_at timestamptz not null,
  created_at timestamptz not null default clock_timestamp()
);

create index secret_bid_offer_history_offer_created_at_idx
  on public.secret_bid_offer_history (offer_id, created_at);

create table public.foal_trade_settlements (
  id uuid primary key default gen_random_uuid(),
  lot_id uuid not null unique references public.foal_trade_lots(id) on delete restrict,
  session_id uuid not null references public.foal_trade_sessions(id) on delete restrict,
  horse_id uuid not null references public.horses(id) on delete restrict,
  status public.foal_trade_settlement_status not null,
  recommended_offer_id uuid references public.secret_bid_offers(id) on delete restrict,
  winning_offer_id uuid references public.secret_bid_offers(id) on delete restrict,
  winner_owner_id uuid references public.owners(id) on delete restrict,
  amount bigint check (amount >= 0),
  is_override boolean not null default false,
  override_reason text,
  confirmed_by_user_id uuid references auth.users(id) on delete set null,
  confirmed_at timestamptz not null default clock_timestamp(),
  reason text,
  created_at timestamptz not null default now(),
  constraint foal_trade_settlements_outcome_check check (
    (status = 'SOLD'::public.foal_trade_settlement_status
      and recommended_offer_id is not null
      and winning_offer_id is not null
      and winner_owner_id is not null
      and amount is not null)
    or
    (status = 'UNSOLD'::public.foal_trade_settlement_status
      and recommended_offer_id is null
      and winning_offer_id is null
      and winner_owner_id is null
      and amount is null)
  ),
  constraint foal_trade_settlements_override_check check (
    (status = 'UNSOLD'::public.foal_trade_settlement_status
      and not is_override
      and override_reason is null)
    or
    (status = 'SOLD'::public.foal_trade_settlement_status
      and not is_override
      and winning_offer_id = recommended_offer_id
      and override_reason is null)
    or
    (status = 'SOLD'::public.foal_trade_settlement_status
      and is_override
      and winning_offer_id <> recommended_offer_id
      and length(btrim(override_reason)) > 0)
  )
);

create unique index foal_trade_settlements_winning_offer_unique_idx
  on public.foal_trade_settlements (winning_offer_id)
  where winning_offer_id is not null;

-- One successful settlement must have exactly one ledger debit, even if a
-- privileged caller accidentally bypasses the RPC in the future.
create unique index financial_transactions_foal_trade_settlement_once_idx
  on public.financial_transactions (source_entity_type, source_entity_id)
  where source_entity_type = 'FOAL_TRADE_SETTLEMENT'
    and source_entity_id is not null;

create function public.prevent_foal_trade_session_year_change()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.wp_year is distinct from old.wp_year
    and exists (
      select 1
      from public.foal_trade_lots
      where session_id = old.id
    ) then
    raise exception 'a foal trade session year cannot change after lots exist'
      using errcode = '23514';
  end if;

  return new;
end;
$$;

create trigger foal_trade_sessions_prevent_year_change
before update of wp_year on public.foal_trade_sessions
for each row execute function public.prevent_foal_trade_session_year_change();

create function public.enforce_foal_trade_lot_horse_eligibility()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_session_year integer;
  v_horse_birth_year integer;
  v_horse_owner_id uuid;
  v_horse_life_stage public.horse_life_stage;
begin
  select wp_year
  into v_session_year
  from public.foal_trade_sessions
  where id = new.session_id
  for key share;

  if not found then
    raise exception 'foal trade session does not exist'
      using errcode = '23503';
  end if;

  select birth_year, owner_id, life_stage
  into v_horse_birth_year, v_horse_owner_id, v_horse_life_stage
  from public.horses
  where id = new.horse_id
  for update;

  if not found then
    raise exception 'horse does not exist'
      using errcode = '23503';
  end if;

  if v_horse_birth_year <> v_session_year
    or v_horse_owner_id is not null
    or v_horse_life_stage <> 'FOAL'::public.horse_life_stage then
    raise exception 'a foal trade lot requires an unowned FOAL born in the session WP year'
      using errcode = '23514';
  end if;

  return new;
end;
$$;

create trigger foal_trade_lots_enforce_horse_eligibility
before insert or update of session_id, horse_id on public.foal_trade_lots
for each row execute function public.enforce_foal_trade_lot_horse_eligibility();

create function public.prevent_foal_trade_minimum_price_conflict()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.minimum_price > old.minimum_price
    and exists (
      select 1
      from public.secret_bid_offers
      where lot_id = old.id
        and status = 'ACTIVE'::public.secret_bid_offer_status
        and amount < new.minimum_price
    ) then
    raise exception 'minimum price cannot exceed an active secret bid'
      using errcode = '23514';
  end if;

  return new;
end;
$$;

create trigger foal_trade_lots_prevent_minimum_price_conflict
before update of minimum_price on public.foal_trade_lots
for each row execute function public.prevent_foal_trade_minimum_price_conflict();

-- A listed foal cannot be assigned through the normal Horse Admin path. The
-- settlement RPC sets a transaction-local guard while assigning its winner.
create function public.prevent_foal_trade_lot_horse_direct_assignment()
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
    and current_setting('horserpg.foal_trade_settlement', true) is distinct from 'on' then
    raise exception 'a foal trade lot horse may only receive an Owner through a controlled settlement'
      using errcode = '23514';
  end if;

  return new;
end;
$$;

create trigger horses_prevent_foal_trade_lot_direct_assignment
before update of owner_id on public.horses
for each row execute function public.prevent_foal_trade_lot_horse_direct_assignment();

create function public.enforce_foal_trade_inquiry_integrity()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_lot_session_id uuid;
begin
  select session_id
  into v_lot_session_id
  from public.foal_trade_lots
  where id = new.lot_id
  for key share;

  if not found or v_lot_session_id <> new.session_id then
    raise exception 'inquiry lot must belong to its session'
      using errcode = '23514';
  end if;

  return new;
end;
$$;

create trigger foal_trade_inquiries_enforce_integrity
before insert or update of session_id, lot_id, owner_id on public.foal_trade_inquiries
for each row execute function public.enforce_foal_trade_inquiry_integrity();

create function public.maintain_foal_trade_inquiry_answer_state()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.gm_comment is null or length(btrim(new.gm_comment)) = 0 then
    new.gm_comment = null;
    new.status = 'REQUESTED'::public.foal_trade_inquiry_status;
    new.answered_at = null;
  elsif tg_op = 'INSERT' or new.gm_comment is distinct from old.gm_comment then
    new.status = 'ANSWERED'::public.foal_trade_inquiry_status;
    new.answered_at = clock_timestamp();
  end if;

  return new;
end;
$$;

create trigger foal_trade_inquiries_maintain_answer_state
before insert or update of gm_comment on public.foal_trade_inquiries
for each row execute function public.maintain_foal_trade_inquiry_answer_state();

create function public.enforce_secret_bid_offer_integrity()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_session_id uuid;
  v_minimum_price bigint;
begin
  select session_id, minimum_price
  into v_session_id, v_minimum_price
  from public.foal_trade_lots
  where id = new.lot_id
  for key share;

  if not found
    or v_session_id <> new.session_id
    or new.amount < v_minimum_price then
    raise exception 'secret bid does not match its lot requirements'
      using errcode = '23514';
  end if;

  return new;
end;
$$;

create trigger secret_bid_offers_enforce_integrity
before insert or update of session_id, lot_id, owner_id, amount on public.secret_bid_offers
for each row execute function public.enforce_secret_bid_offer_integrity();

create function public.enforce_secret_bid_offer_history_integrity()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_lot_id uuid;
  v_owner_id uuid;
begin
  select lot_id, owner_id
  into v_lot_id, v_owner_id
  from public.secret_bid_offers
  where id = new.offer_id
  for key share;

  if not found or v_lot_id <> new.lot_id or v_owner_id <> new.owner_id then
    raise exception 'secret bid history must match its offer'
      using errcode = '23514';
  end if;

  return new;
end;
$$;

create trigger secret_bid_offer_history_enforce_integrity
before insert on public.secret_bid_offer_history
for each row execute function public.enforce_secret_bid_offer_history_integrity();

create function public.prevent_secret_bid_offer_history_mutation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'secret_bid_offer_history is append-only'
    using errcode = '55000';
end;
$$;

create trigger secret_bid_offer_history_prevent_mutation
before update or delete on public.secret_bid_offer_history
for each row execute function public.prevent_secret_bid_offer_history_mutation();

create function public.enforce_foal_trade_settlement_integrity()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_lot_session_id uuid;
  v_lot_horse_id uuid;
  v_offer_lot_id uuid;
  v_offer_session_id uuid;
  v_offer_owner_id uuid;
  v_offer_amount bigint;
  v_recommended_lot_id uuid;
  v_recommended_session_id uuid;
begin
  select session_id, horse_id
  into v_lot_session_id, v_lot_horse_id
  from public.foal_trade_lots
  where id = new.lot_id
  for key share;

  if not found
    or v_lot_session_id <> new.session_id
    or v_lot_horse_id <> new.horse_id then
    raise exception 'settlement must match its lot, session, and horse'
      using errcode = '23514';
  end if;

  if new.status = 'SOLD'::public.foal_trade_settlement_status then
    select lot_id, session_id
    into v_recommended_lot_id, v_recommended_session_id
    from public.secret_bid_offers
    where id = new.recommended_offer_id
    for key share;

    if not found
      or v_recommended_lot_id <> new.lot_id
      or v_recommended_session_id <> new.session_id then
      raise exception 'sold settlement must retain a system recommendation for its lot'
        using errcode = '23514';
    end if;

    select lot_id, session_id, owner_id, amount
    into v_offer_lot_id, v_offer_session_id, v_offer_owner_id, v_offer_amount
    from public.secret_bid_offers
    where id = new.winning_offer_id
    for key share;

    if not found
      or v_offer_lot_id <> new.lot_id
      or v_offer_session_id <> new.session_id
      or v_offer_owner_id <> new.winner_owner_id
      or v_offer_amount <> new.amount then
      raise exception 'sold settlement must match its winning secret bid'
        using errcode = '23514';
    end if;
  end if;

  return new;
end;
$$;

create trigger foal_trade_settlements_enforce_integrity
before insert on public.foal_trade_settlements
for each row execute function public.enforce_foal_trade_settlement_integrity();

create trigger foal_trade_sessions_set_updated_at
before update on public.foal_trade_sessions
for each row execute function public.set_updated_at();

create trigger foal_trade_lots_set_updated_at
before update on public.foal_trade_lots
for each row execute function public.set_updated_at();

create trigger foal_trade_inquiries_set_updated_at
before update on public.foal_trade_inquiries
for each row execute function public.set_updated_at();

create trigger secret_bid_offers_set_updated_at
before update on public.secret_bid_offers
for each row execute function public.set_updated_at();

-- This helper deliberately exposes only the current caller's Owner binding;
-- it avoids RLS recursion and is used by policies and PLAYER-only RPCs.
create function public.current_player_owner_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select owner_id
  from public.user_profiles
  where id = auth.uid()
    and role = 'PLAYER'::public.app_role;
$$;

-- A PLAYER submits a first quote or replaces their own current quote. An
-- identical retry against an already ACTIVE quote is a no-op, preserving its
-- priority. A genuine replacement receives a fresh server timestamp, including
-- a change back to a prior amount, so an old equal-price priority is not kept.
create function public.submit_foal_trade_secret_bid(
  p_lot_id uuid,
  p_amount bigint
)
returns public.secret_bid_offers
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner_id uuid;
  v_session_id uuid;
  v_session_status public.foal_trade_session_status;
  v_session_starts_at timestamptz;
  v_session_ends_at timestamptz;
  v_lot_status public.foal_trade_lot_status;
  v_minimum_price bigint;
  v_offer public.secret_bid_offers%rowtype;
  v_existing_offer boolean := false;
  v_account_funds bigint;
  v_other_frozen bigint;
  v_now timestamptz;
  v_event public.secret_bid_offer_history_event;
begin
  v_owner_id := public.current_player_owner_id();
  if v_owner_id is null then
    raise exception 'only a PLAYER with an Owner binding may submit a secret bid'
      using errcode = '42501';
  end if;

  if p_amount is null or p_amount < 0 then
    raise exception 'secret bid amount must be a non-negative bigint'
      using errcode = '23514';
  end if;

  select session_id, status, minimum_price
  into v_session_id, v_lot_status, v_minimum_price
  from public.foal_trade_lots
  where id = p_lot_id
  for update;

  if not found then
    raise exception 'foal trade lot is unavailable'
      using errcode = 'P0001';
  end if;

  select status, starts_at, ends_at
  into v_session_status, v_session_starts_at, v_session_ends_at
  from public.foal_trade_sessions
  where id = v_session_id
  for update;

  -- All quote mutations for an Owner lock the same parent row. Settlement also
  -- takes this lock before debiting the ledger, preventing concurrent over-freeze.
  select initial_funds
  into v_account_funds
  from public.owners
  where id = v_owner_id
  for update;

  if not found then
    raise exception 'PLAYER Owner binding is invalid'
      using errcode = '23503';
  end if;

  select *
  into v_offer
  from public.secret_bid_offers
  where lot_id = p_lot_id
    and owner_id = v_owner_id
  for update;
  v_existing_offer := found;

  -- Network retries for the exact current ACTIVE quote must never consume a
  -- new equal-price priority or create a duplicate history event.
  if v_existing_offer
    and v_offer.status = 'ACTIVE'::public.secret_bid_offer_status
    and v_offer.amount = p_amount then
    return v_offer;
  end if;

  v_now := clock_timestamp();
  if v_lot_status <> 'LISTED'::public.foal_trade_lot_status
    or v_session_status <> 'OPEN'::public.foal_trade_session_status
    or v_now < v_session_starts_at
    or v_now >= v_session_ends_at then
    raise exception 'foal trade session is no longer accepting secret bids'
      using errcode = 'P0001';
  end if;

  if p_amount < v_minimum_price then
    raise exception 'secret bid is below the public minimum price'
      using errcode = '23514';
  end if;

  select v_account_funds + coalesce(sum(amount), 0)
  into v_account_funds
  from public.financial_transactions
  where owner_id = v_owner_id;

  select coalesce(sum(amount), 0)
  into v_other_frozen
  from public.secret_bid_offers
  where owner_id = v_owner_id
    and status = 'ACTIVE'::public.secret_bid_offer_status
    and id is distinct from v_offer.id;

  if v_account_funds - v_other_frozen - p_amount < 0 then
    raise exception 'secret bid would exceed available funds'
      using errcode = 'P0001';
  end if;

  if v_existing_offer then
    v_event := case
      when v_offer.status = 'WITHDRAWN'::public.secret_bid_offer_status
        then 'REACTIVATED'::public.secret_bid_offer_history_event
      else 'MODIFIED'::public.secret_bid_offer_history_event
    end;

    update public.secret_bid_offers
    set amount = p_amount,
        status = 'ACTIVE'::public.secret_bid_offer_status,
        priority_at = v_now
    where id = v_offer.id
    returning * into v_offer;
  else
    v_event := 'CREATED'::public.secret_bid_offer_history_event;

    insert into public.secret_bid_offers (
      session_id,
      lot_id,
      owner_id,
      amount,
      status,
      priority_at
    )
    values (
      v_session_id,
      p_lot_id,
      v_owner_id,
      p_amount,
      'ACTIVE'::public.secret_bid_offer_status,
      v_now
    )
    returning * into v_offer;
  end if;

  insert into public.secret_bid_offer_history (
    offer_id,
    lot_id,
    owner_id,
    event_type,
    amount,
    priority_at
  )
  values (
    v_offer.id,
    v_offer.lot_id,
    v_offer.owner_id,
    v_event,
    v_offer.amount,
    v_offer.priority_at
  );

  return v_offer;
end;
$$;

create function public.withdraw_foal_trade_secret_bid(p_lot_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner_id uuid;
  v_session_id uuid;
  v_session_status public.foal_trade_session_status;
  v_session_starts_at timestamptz;
  v_session_ends_at timestamptz;
  v_lot_status public.foal_trade_lot_status;
  v_offer public.secret_bid_offers%rowtype;
  v_now timestamptz;
begin
  v_owner_id := public.current_player_owner_id();
  if v_owner_id is null then
    raise exception 'only a PLAYER with an Owner binding may withdraw a secret bid'
      using errcode = '42501';
  end if;

  select session_id, status
  into v_session_id, v_lot_status
  from public.foal_trade_lots
  where id = p_lot_id
  for update;

  if not found then
    raise exception 'foal trade lot is unavailable'
      using errcode = 'P0001';
  end if;

  select status, starts_at, ends_at
  into v_session_status, v_session_starts_at, v_session_ends_at
  from public.foal_trade_sessions
  where id = v_session_id
  for update;

  perform 1
  from public.owners
  where id = v_owner_id
  for update;

  select *
  into v_offer
  from public.secret_bid_offers
  where lot_id = p_lot_id
    and owner_id = v_owner_id
  for update;

  -- A repeated withdrawal is an idempotent no-op. It is intentionally checked
  -- before the deadline gate because it does not mutate a bid after cutoff.
  if found and v_offer.status = 'WITHDRAWN'::public.secret_bid_offer_status then
    return;
  end if;

  v_now := clock_timestamp();
  if v_lot_status <> 'LISTED'::public.foal_trade_lot_status
    or v_session_status <> 'OPEN'::public.foal_trade_session_status
    or v_now < v_session_starts_at
    or v_now >= v_session_ends_at then
    raise exception 'foal trade session is no longer accepting secret bid changes'
      using errcode = 'P0001';
  end if;

  if not found
    or v_offer.status <> 'ACTIVE'::public.secret_bid_offer_status then
    raise exception 'no active secret bid exists for this Owner and lot'
      using errcode = 'P0001';
  end if;

  update public.secret_bid_offers
  set status = 'WITHDRAWN'::public.secret_bid_offer_status
  where id = v_offer.id
  returning * into v_offer;

  insert into public.secret_bid_offer_history (
    offer_id,
    lot_id,
    owner_id,
    event_type,
    amount,
    priority_at
  )
  values (
    v_offer.id,
    v_offer.lot_id,
    v_offer.owner_id,
    'WITHDRAWN'::public.secret_bid_offer_history_event,
    v_offer.amount,
    v_offer.priority_at
  );
end;
$$;

create function public.create_foal_trade_inquiry(p_lot_id uuid)
returns public.foal_trade_inquiries
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner_id uuid;
  v_session_id uuid;
  v_session_status public.foal_trade_session_status;
  v_session_starts_at timestamptz;
  v_session_ends_at timestamptz;
  v_lot_status public.foal_trade_lot_status;
  v_inquiry public.foal_trade_inquiries%rowtype;
  v_now timestamptz;
begin
  v_owner_id := public.current_player_owner_id();
  if v_owner_id is null then
    raise exception 'only a PLAYER with an Owner binding may submit an inquiry'
      using errcode = '42501';
  end if;

  select session_id, status
  into v_session_id, v_lot_status
  from public.foal_trade_lots
  where id = p_lot_id
  for update;

  if not found then
    raise exception 'foal trade lot is unavailable'
      using errcode = 'P0001';
  end if;

  select status, starts_at, ends_at
  into v_session_status, v_session_starts_at, v_session_ends_at
  from public.foal_trade_sessions
  where id = v_session_id
  for update;

  perform 1
  from public.owners
  where id = v_owner_id
  for update;

  select *
  into v_inquiry
  from public.foal_trade_inquiries
  where session_id = v_session_id
    and owner_id = v_owner_id
  for update;

  -- The same request can be safely retried. A request for another lot still
  -- consumes the session-wide one-inquiry allowance and is rejected.
  if found then
    if v_inquiry.lot_id = p_lot_id then
      return v_inquiry;
    end if;

    raise exception 'each Owner may submit only one inquiry per foal trade session'
      using errcode = '23505';
  end if;

  v_now := clock_timestamp();
  if v_lot_status <> 'LISTED'::public.foal_trade_lot_status
    or v_session_status <> 'OPEN'::public.foal_trade_session_status
    or v_now < v_session_starts_at
    or v_now >= v_session_ends_at then
    raise exception 'foal trade session is no longer accepting inquiries'
      using errcode = 'P0001';
  end if;

  insert into public.foal_trade_inquiries (
    session_id,
    lot_id,
    owner_id,
    requested_at
  )
  values (v_session_id, p_lot_id, v_owner_id, v_now)
  returning * into v_inquiry;

  return v_inquiry;
end;
$$;

-- This ungranted internal operation performs both the standard recommendation
-- path and the exceptional GM override path. Public wrappers below make the
-- choice explicit while preserving one transaction and one idempotency point.
create function public.settle_foal_trade_lot_internal(
  p_lot_id uuid,
  p_selected_offer_id uuid,
  p_override_reason text,
  p_reason text
)
returns public.foal_trade_settlements
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_session_id uuid;
  v_horse_id uuid;
  v_lot_status public.foal_trade_lot_status;
  v_session_status public.foal_trade_session_status;
  v_session_ends_at timestamptz;
  v_existing_settlement public.foal_trade_settlements%rowtype;
  v_settlement public.foal_trade_settlements%rowtype;
  v_recommended public.secret_bid_offers%rowtype;
  v_selected public.secret_bid_offers%rowtype;
  v_has_recommended boolean := false;
  v_is_override boolean := false;
  v_override_reason text;
  v_horse_owner_id uuid;
  v_horse_life_stage public.horse_life_stage;
  v_selected_account_funds bigint;
  v_other_active_frozen bigint;
  v_now timestamptz;
begin
  if auth.uid() is null or not public.is_current_user_gm() then
    raise exception 'only a GM may settle a foal trade lot'
      using errcode = '42501';
  end if;

  select session_id, horse_id, status
  into v_session_id, v_horse_id, v_lot_status
  from public.foal_trade_lots
  where id = p_lot_id
  for update;

  if not found then
    raise exception 'foal trade lot does not exist'
      using errcode = 'P0001';
  end if;

  select status, ends_at
  into v_session_status, v_session_ends_at
  from public.foal_trade_sessions
  where id = v_session_id
  for update;

  if not found then
    raise exception 'foal trade session does not exist'
      using errcode = '23503';
  end if;

  select *
  into v_existing_settlement
  from public.foal_trade_settlements
  where lot_id = p_lot_id
  for update;

  if found then
    return v_existing_settlement;
  end if;

  v_now := clock_timestamp();
  if v_now < v_session_ends_at then
    raise exception 'foal trade lot cannot settle before the session deadline'
      using errcode = 'P0001';
  end if;

  if v_session_status not in (
    'OPEN'::public.foal_trade_session_status,
    'CLOSED'::public.foal_trade_session_status,
    'REVIEWING'::public.foal_trade_session_status
  ) then
    raise exception 'foal trade session status is not eligible for settlement'
      using errcode = 'P0001';
  end if;

  if v_lot_status <> 'LISTED'::public.foal_trade_lot_status then
    raise exception 'foal trade lot is not available for settlement'
      using errcode = 'P0001';
  end if;

  select owner_id, life_stage
  into v_horse_owner_id, v_horse_life_stage
  from public.horses
  where id = v_horse_id
  for update;

  if not found
    or v_horse_owner_id is not null
    or v_horse_life_stage <> 'FOAL'::public.horse_life_stage then
    raise exception 'foal trade horse is no longer eligible for settlement'
      using errcode = '23514';
  end if;

  select *
  into v_recommended
  from public.secret_bid_offers
  where lot_id = p_lot_id
    and status = 'ACTIVE'::public.secret_bid_offer_status
  order by amount desc, priority_at asc, id asc
  limit 1
  for update;
  v_has_recommended := found;

  if v_has_recommended then
    if p_selected_offer_id is null then
      v_selected := v_recommended;
    else
      v_override_reason := nullif(btrim(p_override_reason), '');
      if v_override_reason is null then
        raise exception 'GM settlement override requires a non-empty override reason'
          using errcode = '23514';
      end if;

      select *
      into v_selected
      from public.secret_bid_offers
      where id = p_selected_offer_id
        and lot_id = p_lot_id
        and status = 'ACTIVE'::public.secret_bid_offer_status
      for update;

      if not found then
        raise exception 'GM override must select another active offer for this lot'
          using errcode = '23514';
      end if;

      if v_selected.id = v_recommended.id then
        raise exception 'GM override must select an offer other than the system recommendation'
          using errcode = '23514';
      end if;

      v_is_override := true;
    end if;

    select initial_funds
    into v_selected_account_funds
    from public.owners
    where id = v_selected.owner_id
    for update;

    select v_selected_account_funds + coalesce(sum(amount), 0)
    into v_selected_account_funds
    from public.financial_transactions
    where owner_id = v_selected.owner_id;

    -- The selected quote is about to be converted into a ledger debit. All
    -- other ACTIVE quotes remain frozen, so a post-bid GM financial correction
    -- cannot let this settlement make the Owner's available funds negative.
    select coalesce(sum(amount), 0)
    into v_other_active_frozen
    from public.secret_bid_offers
    where owner_id = v_selected.owner_id
      and status = 'ACTIVE'::public.secret_bid_offer_status
      and id <> v_selected.id;

    if v_selected_account_funds - v_selected.amount - v_other_active_frozen < 0 then
      raise exception 'selected Owner no longer has sufficient funds after other active bid freezes'
        using errcode = 'P0001';
    end if;

    insert into public.foal_trade_settlements (
      lot_id,
      session_id,
      horse_id,
      status,
      recommended_offer_id,
      winning_offer_id,
      winner_owner_id,
      amount,
      is_override,
      override_reason,
      confirmed_by_user_id,
      confirmed_at,
      reason
    )
    values (
      p_lot_id,
      v_session_id,
      v_horse_id,
      'SOLD'::public.foal_trade_settlement_status,
      v_recommended.id,
      v_selected.id,
      v_selected.owner_id,
      v_selected.amount,
      v_is_override,
      v_override_reason,
      auth.uid(),
      v_now,
      nullif(btrim(p_reason), '')
    )
    returning * into v_settlement;

    insert into public.financial_transactions (
      owner_id,
      amount,
      transaction_kind,
      source_entity_type,
      source_entity_id,
      effective_at,
      created_by_user_id,
      reason
    )
    values (
      v_selected.owner_id,
      -v_selected.amount,
      'FOAL_TRADE_PURCHASE',
      'FOAL_TRADE_SETTLEMENT',
      v_settlement.id,
      v_now,
      auth.uid(),
      nullif(btrim(p_reason), '')
    );

    perform set_config('horserpg.foal_trade_settlement', 'on', true);
    update public.horses
    set owner_id = v_selected.owner_id,
        life_stage = 'OWNED_FOAL'::public.horse_life_stage
    where id = v_horse_id;

    update public.foal_trade_lots
    set status = 'SOLD'::public.foal_trade_lot_status
    where id = p_lot_id;

    with changed_offers as (
      update public.secret_bid_offers
      set status = case
        when id = v_selected.id then 'WON'::public.secret_bid_offer_status
        else 'LOST'::public.secret_bid_offer_status
      end
      where lot_id = p_lot_id
        and status = 'ACTIVE'::public.secret_bid_offer_status
      returning id, lot_id, owner_id, amount, priority_at, status
    )
    insert into public.secret_bid_offer_history (
      offer_id,
      lot_id,
      owner_id,
      event_type,
      amount,
      priority_at
    )
    select
      id,
      lot_id,
      owner_id,
      case
        when status = 'WON'::public.secret_bid_offer_status
          then 'WON'::public.secret_bid_offer_history_event
        else 'LOST'::public.secret_bid_offer_history_event
      end,
      amount,
      priority_at
    from changed_offers;

    insert into public.audit_logs (
      actor_user_id,
      actor_role,
      action,
      entity_type,
      entity_id,
      before_data,
      after_data,
      reason
    )
    values (
      auth.uid(),
      'GM'::public.app_role,
      case
        when v_is_override then 'FOAL_TRADE_LOT_SETTLED_OVERRIDE'
        else 'FOAL_TRADE_LOT_SETTLED_SOLD'
      end,
      'foal_trade_lots',
      p_lot_id::text,
      jsonb_build_object('lot_status', 'LISTED'),
      jsonb_build_object(
        'settlement_id', v_settlement.id,
        'lot_status', 'SOLD',
        'recommended_offer_id', v_recommended.id,
        'selected_offer_id', v_selected.id,
        'winner_owner_id', v_selected.owner_id,
        'amount', v_selected.amount,
        'is_override', v_is_override
      ),
      coalesce(v_override_reason, nullif(btrim(p_reason), ''))
    );
  else
    if p_selected_offer_id is not null or nullif(btrim(p_override_reason), '') is not null then
      raise exception 'GM override requires a system recommendation and another active offer'
        using errcode = '23514';
    end if;

    insert into public.foal_trade_settlements (
      lot_id,
      session_id,
      horse_id,
      status,
      confirmed_by_user_id,
      confirmed_at,
      reason
    )
    values (
      p_lot_id,
      v_session_id,
      v_horse_id,
      'UNSOLD'::public.foal_trade_settlement_status,
      auth.uid(),
      v_now,
      nullif(btrim(p_reason), '')
    )
    returning * into v_settlement;

    update public.foal_trade_lots
    set status = 'UNSOLD'::public.foal_trade_lot_status
    where id = p_lot_id;

    insert into public.audit_logs (
      actor_user_id,
      actor_role,
      action,
      entity_type,
      entity_id,
      before_data,
      after_data,
      reason
    )
    values (
      auth.uid(),
      'GM'::public.app_role,
      'FOAL_TRADE_LOT_SETTLED_UNSOLD',
      'foal_trade_lots',
      p_lot_id::text,
      jsonb_build_object('lot_status', 'LISTED'),
      jsonb_build_object('settlement_id', v_settlement.id, 'lot_status', 'UNSOLD'),
      nullif(btrim(p_reason), '')
    );
  end if;

  if not exists (
    select 1
    from public.foal_trade_lots
    where session_id = v_session_id
      and status = 'LISTED'::public.foal_trade_lot_status
  ) then
    update public.foal_trade_sessions
    set status = 'SETTLED'::public.foal_trade_session_status
    where id = v_session_id;
  end if;

  return v_settlement;
end;
$$;

-- Normal GM settlement always confirms the system recommendation:
-- amount DESC, priority_at ASC, id ASC.
create function public.settle_foal_trade_lot(
  p_lot_id uuid,
  p_reason text default null
)
returns public.foal_trade_settlements
language sql
security definer
set search_path = ''
as $$
  select public.settle_foal_trade_lot_internal($1, null, null, $2);
$$;

-- An exceptional decision is deliberately a separate RPC. It requires an
-- active non-recommended offer and a non-empty reason, both retained on the
-- settlement and in the GM-only audit log.
create function public.settle_foal_trade_lot_override(
  p_lot_id uuid,
  p_selected_offer_id uuid,
  p_override_reason text
)
returns public.foal_trade_settlements
language sql
security definer
set search_path = ''
as $$
  select public.settle_foal_trade_lot_internal($1, $2, $3, $3);
$$;

revoke all on function public.current_player_owner_id() from public;
revoke all on function public.submit_foal_trade_secret_bid(uuid, bigint) from public;
revoke all on function public.withdraw_foal_trade_secret_bid(uuid) from public;
revoke all on function public.create_foal_trade_inquiry(uuid) from public;
revoke all on function public.settle_foal_trade_lot_internal(uuid, uuid, text, text) from public;
revoke all on function public.settle_foal_trade_lot(uuid, text) from public;
revoke all on function public.settle_foal_trade_lot_override(uuid, uuid, text) from public;

grant execute on function public.current_player_owner_id() to authenticated;
grant execute on function public.submit_foal_trade_secret_bid(uuid, bigint) to authenticated;
grant execute on function public.withdraw_foal_trade_secret_bid(uuid) to authenticated;
grant execute on function public.create_foal_trade_inquiry(uuid) to authenticated;
grant execute on function public.settle_foal_trade_lot(uuid, text) to authenticated;
grant execute on function public.settle_foal_trade_lot_override(uuid, uuid, text) to authenticated;

alter table public.foal_trade_sessions enable row level security;
alter table public.foal_trade_lots enable row level security;
alter table public.foal_trade_inquiries enable row level security;
alter table public.secret_bid_offers enable row level security;
alter table public.secret_bid_offer_history enable row level security;
alter table public.foal_trade_settlements enable row level security;

grant select, insert, update on public.foal_trade_sessions,
  public.foal_trade_lots
to authenticated;

grant select, update on public.foal_trade_inquiries to authenticated;

grant select on public.secret_bid_offers,
  public.secret_bid_offer_history,
  public.foal_trade_settlements
to authenticated;

create policy foal_trade_sessions_select_authenticated
on public.foal_trade_sessions
for select to authenticated
using (true);

create policy foal_trade_sessions_write_gm
on public.foal_trade_sessions
for all to authenticated
using (public.is_current_user_gm())
with check (public.is_current_user_gm());

create policy foal_trade_lots_select_authenticated
on public.foal_trade_lots
for select to authenticated
using (true);

create policy foal_trade_lots_write_gm
on public.foal_trade_lots
for all to authenticated
using (public.is_current_user_gm())
with check (public.is_current_user_gm());

create policy foal_trade_inquiries_select_owner_or_gm
on public.foal_trade_inquiries
for select to authenticated
using (
  owner_id = public.current_player_owner_id()
  or public.is_current_user_gm()
);

create policy foal_trade_inquiries_update_gm
on public.foal_trade_inquiries
for update to authenticated
using (public.is_current_user_gm())
with check (public.is_current_user_gm());

create policy secret_bid_offers_select_owner_or_gm
on public.secret_bid_offers
for select to authenticated
using (
  owner_id = public.current_player_owner_id()
  or public.is_current_user_gm()
);

create policy secret_bid_offer_history_select_owner_or_gm
on public.secret_bid_offer_history
for select to authenticated
using (
  owner_id = public.current_player_owner_id()
  or public.is_current_user_gm()
);

-- Settlement rows contain winning-bid amounts. Keep them GM-only until a
-- Public results use the narrowly scoped projection below. Direct settlement
-- rows remain GM-only because they contain internal offer references and notes.
create policy foal_trade_settlements_select_gm
on public.foal_trade_settlements
for select to authenticated
using (public.is_current_user_gm());

-- This security-barrier view intentionally exposes only the final public
-- outcome. It never exposes a bid identifier, non-winning offer, quote history,
-- GM-only reason, or confirmer identity.
create view public.foal_trade_public_settlements
with (security_barrier = true)
as
select
  lot_id,
  session_id,
  horse_id,
  status,
  winner_owner_id,
  amount,
  confirmed_at
from public.foal_trade_settlements;

grant select on public.foal_trade_public_settlements to authenticated;

commit;
