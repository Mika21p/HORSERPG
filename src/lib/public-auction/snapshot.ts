import "server-only";

import type { SupabaseClient } from "@supabase/supabase-js";

import type { PublicAuctionSnapshot } from "@/lib/public-auction/types";

export class PublicAuctionSnapshotError extends Error {}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isString(value: unknown): value is string {
  return typeof value === "string";
}

function isNumberOrString(value: unknown): value is number | string {
  return typeof value === "number" || typeof value === "string";
}

function isNullableString(value: unknown): value is string | null {
  return value === null || isString(value);
}

function isSnapshot(value: unknown): value is PublicAuctionSnapshot {
  if (
    !isRecord(value)
    || !isRecord(value.event)
    || !isNullableRecord(value.currentLot)
    || !isNullableRecord(value.currentRound)
    || !Array.isArray(value.bids)
    || !isNullableRecord(value.settlement)
  ) {
    return false;
  }

  const { event, currentLot, currentRound, bids, settlement } = value;
  if (
    !isString(event.id)
    || !isString(event.status)
    || typeof event.wp_year !== "number"
    || !isNumberOrString(event.minimum_increment)
  ) {
    return false;
  }

  if (currentLot && !isCurrentLot(currentLot)) {
    return false;
  }

  if (currentRound && !isCurrentRound(currentRound)) {
    return false;
  }

  if (!bids.every(isBid)) {
    return false;
  }

  return !settlement || isSettlement(settlement);
}

function isNullableRecord(value: unknown): value is Record<string, unknown> | null {
  return value === null || isRecord(value);
}

function isCurrentLot(value: Record<string, unknown>): boolean {
  return isString(value.id)
    && typeof value.lot_number === "number"
    && isString(value.horse_id)
    && isNumberOrString(value.starting_price)
    && isNumberOrString(value.evaluation_value)
    && isString(value.revealed_at)
    && isString(value.status)
    && (value.horse === null || isHorse(value.horse))
    && Array.isArray(value.reviews)
    && value.reviews.every(isReview);
}

function isHorse(value: unknown): boolean {
  if (!isRecord(value) || !Array.isArray(value.factors)) {
    return false;
  }

  return isString(value.id)
    && isNumberOrString(value.horse_number)
    && isString(value.foal_name)
    && isNullableString(value.translated_name)
    && isString(value.sex)
    && isString(value.coat_color)
    && isString(value.sire_name)
    && isString(value.sire_line)
    && isString(value.broodmare_sire_name)
    && value.factors.every((factor) => isRecord(factor) && isString(factor.factor_kind) && isString(factor.factor_name));
}

function isReview(value: unknown): boolean {
  return isRecord(value)
    && typeof value.slot === "number"
    && typeof value.stars === "number"
    && isString(value.comment);
}

function isCurrentRound(value: Record<string, unknown>): boolean {
  return isString(value.id)
    && typeof value.round_number === "number"
    && isString(value.status)
    && isNullableString(value.opened_at)
    && isNullableString(value.close_at)
    && isNullableString(value.no_bid_deadline)
    && (value.current_price === null || isNumberOrString(value.current_price))
    && isNullableString(value.current_winner_owner_id);
}

function isBid(value: unknown): boolean {
  if (!isRecord(value) || !isString(value.id) || !isNumberOrString(value.amount) || !isString(value.accepted_at)) {
    return false;
  }

  return value.owner === null || (
    isRecord(value.owner)
    && isString(value.owner.id)
    && isString(value.owner.display_name)
  );
}

function isSettlement(value: Record<string, unknown>): boolean {
  return isString(value.status)
    && isNullableString(value.winner_owner_id)
    && (value.amount === null || isNumberOrString(value.amount))
    && isString(value.confirmed_at);
}

/**
 * Reads the complete narrow, PLAYER-safe auction display model in one atomic
 * PostgreSQL statement. The authenticated caller's RLS context is preserved;
 * this helper intentionally never uses a service-role client.
 */
export async function getPublicAuctionSnapshot(
  supabase: SupabaseClient,
  eventId: string,
): Promise<PublicAuctionSnapshot | null> {
  const { data, error } = await supabase.rpc("get_public_auction_snapshot", {
    p_event_id: eventId,
  });

  if (error) {
    throw new PublicAuctionSnapshotError("Unable to read the atomic auction snapshot.");
  }

  if (data === null) {
    return null;
  }

  if (!isSnapshot(data)) {
    throw new PublicAuctionSnapshotError("The atomic auction snapshot has an invalid shape.");
  }

  return data;
}
