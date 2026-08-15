-- Owner-private, read-only funds summary for the foal-trade UI.
-- This migration intentionally adds no persisted balance fields.

begin;

create function public.get_current_owner_funds()
returns table (
  account_funds bigint,
  foal_trade_frozen_funds bigint,
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
    raise exception 'an authenticated PLAYER is required to read Owner funds'
      using errcode = '42501';
  end if;

  select profile.owner_id
  into v_owner_id
  from public.user_profiles as profile
  where profile.id = auth.uid()
    and profile.role = 'PLAYER'::public.app_role;

  if v_owner_id is null then
    raise exception 'only a PLAYER with a valid Owner binding may read Owner funds'
      using errcode = '42501';
  end if;

  -- The ACTIVE state is the existing canonical freeze definition used by both
  -- submit_foal_trade_secret_bid and settle_foal_trade_lot_internal. A
  -- settlement changes every active offer on its Lot to WON or LOST in the
  -- same transaction as the ledger debit, preventing a double deduction here.
  return query
  select
    owner.initial_funds + ledger.transaction_total as account_funds,
    frozen.active_offer_total as foal_trade_frozen_funds,
    owner.initial_funds + ledger.transaction_total - frozen.active_offer_total as available_funds
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
  ) as frozen
  where owner.id = v_owner_id;

  if not found then
    raise exception 'PLAYER Owner binding is invalid'
      using errcode = '23503';
  end if;
end;
$$;

revoke all on function public.get_current_owner_funds() from public;
revoke execute on function public.get_current_owner_funds() from anon;
revoke execute on function public.get_current_owner_funds() from service_role;
grant execute on function public.get_current_owner_funds() to authenticated;

commit;
