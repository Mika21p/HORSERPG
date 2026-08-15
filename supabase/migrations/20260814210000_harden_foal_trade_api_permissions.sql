-- HorseRPG v0.2 foal-trade API permission hardening.
-- This migration only adjusts ACLs and future default privileges. It does not
-- change foal-trade business logic, RLS policies, views, or function bodies.

begin;

-- The public settlement projection intentionally runs with its owner so that
-- authenticated players can read only the approved final outcome despite the
-- GM-only base settlement table. It must never be accessible to anon, nor be
-- writable by any client-facing role.
revoke all on table public.foal_trade_public_settlements from public;
revoke all on table public.foal_trade_public_settlements from anon;
revoke all on table public.foal_trade_public_settlements from authenticated;
revoke all on table public.foal_trade_public_settlements from service_role;

grant select on table public.foal_trade_public_settlements to authenticated;
grant select on table public.foal_trade_public_settlements to service_role;

-- Trigger-only helpers introduced by the foal-trade schema are never RPCs.
revoke all on function public.prevent_foal_trade_session_year_change() from public, anon, authenticated, service_role;
revoke all on function public.enforce_foal_trade_lot_horse_eligibility() from public, anon, authenticated, service_role;
revoke all on function public.prevent_foal_trade_minimum_price_conflict() from public, anon, authenticated, service_role;
revoke all on function public.prevent_foal_trade_lot_horse_direct_assignment() from public, anon, authenticated, service_role;
revoke all on function public.enforce_foal_trade_inquiry_integrity() from public, anon, authenticated, service_role;
revoke all on function public.maintain_foal_trade_inquiry_answer_state() from public, anon, authenticated, service_role;
revoke all on function public.enforce_secret_bid_offer_integrity() from public, anon, authenticated, service_role;
revoke all on function public.enforce_secret_bid_offer_history_integrity() from public, anon, authenticated, service_role;
revoke all on function public.prevent_secret_bid_offer_history_mutation() from public, anon, authenticated, service_role;
revoke all on function public.enforce_foal_trade_settlement_integrity() from public, anon, authenticated, service_role;

-- This helper is invoked by the inquiry and secret-bid RLS policies and by the
-- PLAYER RPCs. authenticated therefore retains EXECUTE; anon and server roles
-- have no need to invoke it directly.
revoke all on function public.current_player_owner_id() from public, anon, authenticated, service_role;
grant execute on function public.current_player_owner_id() to authenticated;

-- PLAYER-facing RPCs are authenticated-only. Their bodies derive Owner from
-- auth.uid(), never from a client argument.
revoke all on function public.submit_foal_trade_secret_bid(uuid, bigint) from public, anon, authenticated, service_role;
revoke all on function public.withdraw_foal_trade_secret_bid(uuid) from public, anon, authenticated, service_role;
revoke all on function public.create_foal_trade_inquiry(uuid) from public, anon, authenticated, service_role;

grant execute on function public.submit_foal_trade_secret_bid(uuid, bigint) to authenticated;
grant execute on function public.withdraw_foal_trade_secret_bid(uuid) to authenticated;
grant execute on function public.create_foal_trade_inquiry(uuid) to authenticated;

-- The internal settlement implementation is callable only by the two
-- SECURITY DEFINER wrappers below. The wrappers execute as postgres and can
-- therefore call it without granting direct client access.
revoke all on function public.settle_foal_trade_lot_internal(uuid, uuid, text, text) from public, anon, authenticated, service_role;

-- The public settlement RPCs remain callable by authenticated clients, but
-- their shared internal implementation enforces auth.uid() and GM status.
revoke all on function public.settle_foal_trade_lot(uuid, text) from public, anon, authenticated, service_role;
revoke all on function public.settle_foal_trade_lot_override(uuid, uuid, text) from public, anon, authenticated, service_role;

grant execute on function public.settle_foal_trade_lot(uuid, text) to authenticated;
grant execute on function public.settle_foal_trade_lot_override(uuid, uuid, text) to authenticated;

-- Supabase's default ACLs can otherwise grant newly created public objects to
-- anon or PUBLIC. Future migrations remain responsible for explicitly granting
-- the minimum authenticated/service_role permissions they require.
alter default privileges for role postgres in schema public
  revoke execute on functions from public;
alter default privileges for role postgres in schema public
  revoke execute on functions from anon;
alter default privileges for role postgres in schema public
  revoke all on tables from anon;

commit;
