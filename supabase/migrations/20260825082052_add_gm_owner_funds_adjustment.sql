-- GM-only, append-only manual Owner funds adjustments.
-- This migration adds no persisted balance fields: all balances remain derived
-- from initial_funds, financial transactions, and current auction freezes.

begin;

-- A stable request id is the immutable source locator for a manual adjustment.
-- It makes a browser/network retry idempotent and prevents duplicate ledger
-- entries even if two requests race against different Owner rows.
create unique index financial_transactions_gm_manual_adjustment_request_unique_idx
  on public.financial_transactions (source_entity_type, source_entity_id)
  where source_entity_type = 'GM_OWNER_FUNDS_ADJUSTMENT'
    and source_entity_id is not null;

-- Internal calculation helper. It has no direct client EXECUTE privilege;
-- GM-only read/write wrappers below are the public API. Keeping the freeze
-- definition here makes the adjustment guard and GM display use one formula.
create function public.owner_financial_summary_for_owner(p_owner_id uuid)
returns table (
  account_funds bigint,
  foal_trade_frozen_funds bigint,
  public_auction_frozen_funds bigint,
  total_frozen_funds bigint,
  available_funds bigint
)
language sql
stable
security definer
set search_path = ''
as $$
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
  where owner.id = p_owner_id;
$$;

create function public.get_gm_owner_financial_summary(p_owner_id uuid)
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
begin
  if auth.uid() is null or not public.is_current_user_gm() then
    raise exception 'only a GM may read an Owner financial summary'
      using errcode = '42501';
  end if;

  if p_owner_id is null
    or not exists (select 1 from public.owners where id = p_owner_id) then
    raise exception 'Owner does not exist'
      using errcode = '23503';
  end if;

  return query
  select *
  from public.owner_financial_summary_for_owner(p_owner_id);
end;
$$;

create function public.adjust_owner_funds(
  p_owner_id uuid,
  p_amount bigint,
  p_reason text,
  p_request_id uuid
)
returns public.financial_transactions
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner public.owners%rowtype;
  v_existing public.financial_transactions%rowtype;
  v_transaction public.financial_transactions%rowtype;
  v_before record;
  v_after record;
  v_reason text := nullif(btrim(p_reason), '');
begin
  if auth.uid() is null or not public.is_current_user_gm() then
    raise exception 'only a GM may adjust Owner funds'
      using errcode = '42501';
  end if;

  if p_owner_id is null or p_amount is null or p_amount = 0 or p_request_id is null then
    raise exception 'Owner, non-zero adjustment amount, and request id are required'
      using errcode = '22023';
  end if;

  if v_reason is null then
    raise exception 'a manual Owner funds adjustment reason is required'
      using errcode = '22023';
  end if;

  -- This serializes retries by request id before the shared Owner lock below.
  perform pg_advisory_xact_lock(hashtextextended(p_request_id::text, 0));

  select *
  into v_existing
  from public.financial_transactions
  where source_entity_type = 'GM_OWNER_FUNDS_ADJUSTMENT'
    and source_entity_id = p_request_id;

  if found then
    if v_existing.owner_id = p_owner_id
      and v_existing.amount = p_amount
      and v_existing.transaction_kind = 'GM_MANUAL_ADJUSTMENT'
      and v_existing.reason is not distinct from v_reason then
      return v_existing;
    end if;

    raise exception 'idempotency key conflict: request id was already used with different adjustment facts'
      using errcode = '23514';
  end if;

  -- Owner is the shared serialization point with foal-trade and public-auction
  -- bid paths. The financial position is read only after this lock is held.
  select *
  into v_owner
  from public.owners
  where id = p_owner_id
  for update;

  if not found then
    raise exception 'Owner does not exist'
      using errcode = '23503';
  end if;

  select *
  into v_before
  from public.owner_financial_summary_for_owner(v_owner.id);

  if v_before.account_funds + p_amount < 0
    or v_before.available_funds + p_amount < 0 then
    raise exception 'Owner funds adjustment would make account funds or available funds negative'
      using errcode = '23514';
  end if;

  insert into public.financial_transactions (
    owner_id,
    amount,
    transaction_kind,
    source_entity_type,
    source_entity_id,
    effective_at,
    created_by_user_id,
    reason
  ) values (
    v_owner.id,
    p_amount,
    'GM_MANUAL_ADJUSTMENT',
    'GM_OWNER_FUNDS_ADJUSTMENT',
    p_request_id,
    clock_timestamp(),
    auth.uid(),
    v_reason
  ) returning * into v_transaction;

  select *
  into v_after
  from public.owner_financial_summary_for_owner(v_owner.id);

  insert into public.audit_logs (
    actor_user_id,
    actor_role,
    action,
    entity_type,
    entity_id,
    before_data,
    after_data,
    reason,
    request_id
  ) values (
    auth.uid(),
    'GM'::public.app_role,
    'OWNER_FUNDS_MANUAL_ADJUSTED',
    'owners',
    v_owner.id::text,
    jsonb_build_object(
      'account_funds', v_before.account_funds,
      'foal_trade_frozen_funds', v_before.foal_trade_frozen_funds,
      'public_auction_frozen_funds', v_before.public_auction_frozen_funds,
      'total_frozen_funds', v_before.total_frozen_funds,
      'available_funds', v_before.available_funds
    ),
    jsonb_build_object(
      'financial_transaction_id', v_transaction.id,
      'amount', v_transaction.amount,
      'transaction_kind', v_transaction.transaction_kind,
      'account_funds', v_after.account_funds,
      'foal_trade_frozen_funds', v_after.foal_trade_frozen_funds,
      'public_auction_frozen_funds', v_after.public_auction_frozen_funds,
      'total_frozen_funds', v_after.total_frozen_funds,
      'available_funds', v_after.available_funds
    ),
    v_reason,
    p_request_id
  );

  return v_transaction;
end;
$$;

revoke all on function public.owner_financial_summary_for_owner(uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.get_gm_owner_financial_summary(uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.adjust_owner_funds(uuid, bigint, text, uuid)
  from public, anon, authenticated, service_role;

grant execute on function public.get_gm_owner_financial_summary(uuid)
  to authenticated;
grant execute on function public.adjust_owner_funds(uuid, bigint, text, uuid)
  to authenticated;

comment on function public.adjust_owner_funds(uuid, bigint, text, uuid) is
  'GM-only, append-only manual Owner balance adjustment with request-id idempotency and audit.';

commit;
