import type { PublicAuctionSnapshot } from "@/lib/public-auction/types";

export type AuctionMoney = number | string | bigint | null | undefined;

const ZERO = BigInt(0);
const TEN_THOUSAND = BigInt(10_000);
const HUNDRED_THOUSAND = BigInt(100_000);

export function toAuctionBigInt(value: AuctionMoney): bigint | null {
  if (value === null || value === undefined) {
    return null;
  }

  try {
    return BigInt(value);
  } catch {
    return null;
  }
}

/** Accepts either a raw integer amount or a Chinese "万" shorthand. */
export function parseAuctionAmount(value: string): bigint | null {
  const normalized = value.replace(/[，,\s]/g, "").trim();
  const match = normalized.match(/^(\d+)(万)?$/);
  if (!match) {
    return null;
  }

  try {
    return BigInt(match[1]) * (match[2] ? TEN_THOUSAND : BigInt(1));
  } catch {
    return null;
  }
}

export function formatAuctionInput(value: AuctionMoney) {
  const amount = toAuctionBigInt(value);
  return amount === null ? "" : amount.toString();
}

export function isAuctionAmountIncrement(value: bigint) {
  return value >= ZERO && value % HUNDRED_THOUSAND === ZERO;
}

export function getBidSuggestion(snapshot: PublicAuctionSnapshot | null): bigint | null {
  const lot = snapshot?.currentLot;
  const round = snapshot?.currentRound;
  if (!lot || !round || !["OPEN_WAITING", "BIDDING"].includes(round.status)) {
    return null;
  }

  if (round.status === "OPEN_WAITING") {
    return toAuctionBigInt(lot.starting_price);
  }

  const currentPrice = toAuctionBigInt(round.current_price);
  const minimumIncrement = toAuctionBigInt(snapshot?.event.minimum_increment);
  return currentPrice === null || minimumIncrement === null ? null : currentPrice + minimumIncrement;
}

export function formatPublicAuctionStatus(status: string) {
  const labels: Record<string, string> = {
    DRAFT: "草稿",
    OPEN: "开放中",
    CLOSED: "已关闭",
    SETTLED: "已结算",
    QUEUED: "待展示",
    OPEN_WAITING: "等待首笔报价",
    BIDDING: "竞价中",
    SOLD: "已成交",
    PASSED: "流拍",
    VOIDED: "已作废",
  };

  return labels[status] ?? "未知状态";
}

export function publicAuctionConnectionLabel(state: string) {
  if (state === "connected") {
    return "实时同步已连接";
  }
  if (state === "connecting" || state === "reconnecting") {
    return "正在恢复实时连接……";
  }
  if (state === "disconnected" || state === "error") {
    return "实时连接暂时中断，当前页面仍以数据库快照为准。";
  }
  return "正在读取权威拍卖状态……";
}

export function auctionRoundDeadline(snapshot: PublicAuctionSnapshot | null) {
  const round = snapshot?.currentRound;
  if (!round) {
    return null;
  }
  return round.status === "BIDDING" ? round.close_at : round.status === "OPEN_WAITING" ? round.no_bid_deadline : null;
}
