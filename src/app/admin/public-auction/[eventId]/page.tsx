import { notFound } from "next/navigation";

import {
  PublicAuctionAdminConsole,
  type AdminAuctionBid,
  type AdminAuctionEvent,
  type AdminAuctionFactor,
  type AdminAuctionHorse,
  type AdminAuctionLot,
  type AdminAuctionOwner,
  type AdminAuctionReview,
  type AdminAuctionRollbackRequest,
  type AdminAuctionRound,
  type AdminAuctionSettlement,
} from "@/components/public-auction/public-auction-admin-console";
import { requireGM } from "@/lib/auth/session";

export const dynamic = "force-dynamic";

type PageProps = { params: Promise<{ eventId: string }> };

export default async function AdminPublicAuctionEventPage({ params }: PageProps) {
  const [{ eventId }, { supabase }] = await Promise.all([params, requireGM()]);
  const { data: event } = await supabase
    .from("public_auction_events")
    .select("id, name, wp_year, status, minimum_increment")
    .eq("id", eventId)
    .maybeSingle();
  if (!event) notFound();

  const { data: lotRows } = await supabase
    .from("public_auction_lots")
    .select("id, horse_id, lot_number, starting_price, evaluation_value, revealed_at, status, current_round_id, current_price, current_winner_owner_id")
    .eq("event_id", eventId)
    .order("lot_number");
  const lots = (lotRows ?? []) as unknown as AdminAuctionLot[];
  const lotIds = lots.map((lot) => lot.id);

  const [horseResult, factorResult, reviewResult, roundResult, bidResult, ownerResult, settlementResult, rollbackResult] = await Promise.all([
    supabase.from("horses").select("id, horse_number, foal_name, translated_name, sex, coat_color, sire_name, sire_line, broodmare_sire_name, owner_id, life_stage").order("horse_number"),
    supabase.from("horse_factors").select("horse_id, factor_kind, factor_name").order("factor_kind").order("factor_name"),
    lotIds.length ? supabase.from("public_auction_lot_reviews").select("id, lot_id, slot, stars, comment").in("lot_id", lotIds).order("slot") : Promise.resolve({ data: [] }),
    lotIds.length ? supabase.from("public_auction_rounds").select("id, lot_id, round_number, status, current_price, current_winner_owner_id, close_at, no_bid_deadline, closed_at").in("lot_id", lotIds).order("round_number") : Promise.resolve({ data: [] }),
    lotIds.length ? supabase.from("public_auction_bids").select("id, lot_id, round_id, owner_id, amount, accepted_at").in("lot_id", lotIds).order("accepted_at") : Promise.resolve({ data: [] }),
    supabase.from("owners").select("id, display_name").order("display_name"),
    lotIds.length ? supabase.from("public_auction_settlements").select("id, lot_id, round_id, status, winner_owner_id, amount, confirmed_at").in("lot_id", lotIds).order("confirmed_at", { ascending: false }) : Promise.resolve({ data: [] }),
    lotIds.length ? supabase.from("public_auction_rollback_requests").select("id, lot_id, round_id, settlement_id, reason, status, expected_confirmation, requested_at, confirmed_at, executed_at, new_round_id").in("lot_id", lotIds).order("requested_at", { ascending: false }) : Promise.resolve({ data: [] }),
  ]);

  return <PublicAuctionAdminConsole
    event={event as unknown as AdminAuctionEvent}
    lots={lots}
    horses={(horseResult.data ?? []) as unknown as AdminAuctionHorse[]}
    factors={(factorResult.data ?? []) as unknown as AdminAuctionFactor[]}
    reviews={(reviewResult.data ?? []) as unknown as AdminAuctionReview[]}
    rounds={(roundResult.data ?? []) as unknown as AdminAuctionRound[]}
    bids={(bidResult.data ?? []) as unknown as AdminAuctionBid[]}
    owners={(ownerResult.data ?? []) as unknown as AdminAuctionOwner[]}
    settlements={(settlementResult.data ?? []) as unknown as AdminAuctionSettlement[]}
    rollbackRequests={(rollbackResult.data ?? []) as unknown as AdminAuctionRollbackRequest[]}
  />;
}
