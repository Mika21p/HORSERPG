export type PublicAuctionSnapshot = {
  event: {
    id: string;
    status: string;
    wp_year: number;
    minimum_increment: number | string;
  };
  currentLot: {
    id: string;
    lot_number: number;
    horse_id: string;
    starting_price: number | string;
    evaluation_value: number | string;
    revealed_at: string;
    status: string;
    horse: {
      id: string;
      horse_number: number | string;
      foal_name: string;
      translated_name: string | null;
      sex: string;
      coat_color: string;
      sire_name: string;
      sire_line: string;
      broodmare_sire_name: string;
      factors: { factor_kind: string; factor_name: string }[];
    } | null;
    reviews: {
      slot: number;
      stars: number;
      comment: string;
    }[];
  } | null;
  currentRound: {
    id: string;
    round_number: number;
    status: string;
    opened_at: string | null;
    close_at: string | null;
    no_bid_deadline: string | null;
    current_price: number | string | null;
    current_winner_owner_id: string | null;
  } | null;
  bids: {
    id: string;
    amount: number | string;
    accepted_at: string;
    owner: { id: string; display_name: string } | null;
  }[];
  settlement: {
    status: string;
    winner_owner_id: string | null;
    amount: number | string | null;
    confirmed_at: string;
  } | null;
};

export type PublicAuctionRealtimeEvent = {
  kind: "EVENT_CHANGED" | "LOT_REVEALED" | "LOT_CHANGED" | "ROUND_CHANGED" | "BID_ACCEPTED";
  event_id: string;
  lot_id?: string | null;
  round_id?: string | null;
  bid_id?: string | null;
};
