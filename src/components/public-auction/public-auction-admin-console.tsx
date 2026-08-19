"use client";

import { useMemo, useRef, useState } from "react";
import { useRouter } from "next/navigation";

import { formatDateTime, formatGameMoney } from "@/lib/format";
import { formatPublicAuctionStatus, parseAuctionAmount } from "@/lib/public-auction/ui";
import { usePublicAuctionRealtime } from "@/lib/public-auction/use-public-auction-realtime";
import { createClient } from "@/lib/supabase/client";

type Money = number | string;

export type AdminAuctionEvent = {
  id: string;
  name: string;
  wp_year: number;
  status: string;
  minimum_increment: Money;
};

export type AdminAuctionLot = {
  id: string;
  horse_id: string;
  lot_number: number;
  starting_price: Money;
  evaluation_value: Money;
  revealed_at: string | null;
  status: string;
  current_round_id: string | null;
  current_price: Money | null;
  current_winner_owner_id: string | null;
};

export type AdminAuctionHorse = {
  id: string;
  horse_number: Money;
  foal_name: string;
  translated_name: string | null;
  sex: string;
  coat_color: string;
  sire_name: string;
  sire_line: string;
  broodmare_sire_name: string;
  owner_id: string | null;
  life_stage: string;
};

export type AdminAuctionFactor = { horse_id: string; factor_kind: string; factor_name: string };
export type AdminAuctionReview = { id: string; lot_id: string; slot: number; stars: number; comment: string };
export type AdminAuctionRound = { id: string; lot_id: string; round_number: number; status: string; current_price: Money | null; current_winner_owner_id: string | null; close_at: string | null; no_bid_deadline: string | null; closed_at: string | null };
export type AdminAuctionBid = { id: string; lot_id: string; round_id: string; owner_id: string; amount: Money; accepted_at: string };
export type AdminAuctionOwner = { id: string; display_name: string };
export type AdminAuctionSettlement = { id: string; lot_id: string; round_id: string; status: string; winner_owner_id: string | null; amount: Money | null; confirmed_at: string };
export type AdminAuctionRollbackRequest = { id: string; lot_id: string; round_id: string; settlement_id: string; reason: string; status: string; expected_confirmation: string; requested_at: string; confirmed_at: string | null; executed_at: string | null; new_round_id: string | null };

type PendingConfirmation = {
  action: string;
  rpc: string;
  args: Record<string, unknown>;
  success: string;
  message: string;
};

type PublicAuctionAdminConsoleProps = {
  event: AdminAuctionEvent;
  lots: AdminAuctionLot[];
  horses: AdminAuctionHorse[];
  factors: AdminAuctionFactor[];
  reviews: AdminAuctionReview[];
  rounds: AdminAuctionRound[];
  bids: AdminAuctionBid[];
  owners: AdminAuctionOwner[];
  settlements: AdminAuctionSettlement[];
  rollbackRequests: AdminAuctionRollbackRequest[];
};

function adminError(message: string | undefined) {
  const normalized = message?.toLowerCase() ?? "";
  if (normalized.includes("only a gm")) return "当前操作仅限 GM。";
  if (normalized.includes("all five") || normalized.includes("review")) return "五份评价尚未完整，或该 Lot 已展示而不能再普通编辑。";
  if (normalized.includes("event must be open")) return "请先将 Event 明确设为开放中。";
  if (normalized.includes("sequential") || normalized.includes("earlier")) return "前一个 Lot 尚未最终完成，不能提前展示下一匹。";
  if (normalized.includes("deadline") || normalized.includes("close only")) return "服务器截止时间尚未到达，无法关闭当前竞价。";
  if (normalized.includes("closed public auction")) return "仅已关闭的当前 Round 可以执行此结算。";
  if (normalized.includes("reopen")) return "只有未结算的 CLOSED Lot 可以按普通流程重新开放。";
  if (normalized.includes("confirmation")) return "紧急回滚确认文本不匹配。";
  if (normalized.includes("unstarted draft") || normalized.includes("live or settled history")) return "只能移除尚未展示、未开始且没有 Bid、结算或回滚历史的草稿配置。";
  if (normalized.includes("non-empty removal reason")) return "移除草稿必须填写非空原因。";
  if (normalized.includes("requires")) return "该操作不满足数据库要求，请检查 Event、Lot、Round 与资金状态。";
  return "操作未被服务器接受。请刷新页面后确认当前状态。";
}

function ReviewEditor({ lot, review, onSave, busy }: { lot: AdminAuctionLot; review: AdminAuctionReview | undefined; onSave: (slot: number, stars: number, comment: string) => void; busy: boolean }) {
  const [stars, setStars] = useState(String(review?.stars ?? 5));
  const [comment, setComment] = useState(review?.comment ?? "");
  const frozen = Boolean(lot.revealed_at);
  return <form className="rounded-lg border border-stone-800 bg-stone-950/50 p-3" onSubmit={(event) => { event.preventDefault(); onSave(review?.slot ?? Number(event.currentTarget.dataset.slot), Number(stars), comment); }} data-slot={review?.slot ?? undefined}>
    <div className="flex items-center justify-between gap-3"><p className="text-sm font-semibold text-stone-200">评价 {review?.slot ?? "—"}</p>{frozen && <span className="text-xs text-amber-100">已展示，普通编辑已冻结</span>}</div>
    <div className="mt-3 grid gap-3 sm:grid-cols-[8rem_1fr_auto]"><select className="admin-input mt-0" disabled={frozen || busy} onChange={(event) => setStars(event.target.value)} value={stars}>{[1, 2, 3, 4, 5].map((value) => <option key={value} value={value}>{"★".repeat(value)}{"☆".repeat(5 - value)}</option>)}</select><input className="admin-input mt-0" disabled={frozen || busy} onChange={(event) => setComment(event.target.value)} placeholder="GM 评价" required value={comment} /><button className="rounded-lg border border-stone-600 px-3 py-2 text-sm text-stone-200 hover:border-amber-300 hover:text-amber-200 disabled:cursor-not-allowed disabled:opacity-60" disabled={frozen || busy} type="submit">{busy ? "保存中…" : "保存"}</button></div>
  </form>;
}

export function PublicAuctionAdminConsole({ event, lots, horses, factors, reviews, rounds, bids, owners, settlements, rollbackRequests }: PublicAuctionAdminConsoleProps) {
  const router = useRouter();
  const supabaseRef = useRef<ReturnType<typeof createClient> | null>(null);
  const { connectionState, refreshSnapshot, snapshot } = usePublicAuctionRealtime(event.id);
  const [busyAction, setBusyAction] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [createLot, setCreateLot] = useState({ horseId: "", lotNumber: String((Math.max(0, ...lots.map((lot) => lot.lot_number)) + 1)), startingPrice: "", evaluationValue: "" });
  const [rollbackReasons, setRollbackReasons] = useState<Record<string, string>>({});
  const [rollbackConfirmations, setRollbackConfirmations] = useState<Record<string, string>>({});
  const [draftRemovalReasons, setDraftRemovalReasons] = useState({ event: "", lot: "" });
  const [completedRollbackRequestIds, setCompletedRollbackRequestIds] = useState<string[]>([]);
  const [locallySavedReviewSlots, setLocallySavedReviewSlots] = useState<Record<string, true>>({});
  const [pendingConfirmation, setPendingConfirmation] = useState<PendingConfirmation | null>(null);

  const getSupabase = () => {
    if (!supabaseRef.current) supabaseRef.current = createClient();
    return supabaseRef.current;
  };
  const ownerById = useMemo(() => new Map(owners.map((owner) => [owner.id, owner.display_name])), [owners]);
  const horseById = useMemo(() => new Map(horses.map((horse) => [horse.id, horse])), [horses]);
  const factorsByHorse = useMemo(() => { const map = new Map<string, AdminAuctionFactor[]>(); factors.forEach((factor) => map.set(factor.horse_id, [...(map.get(factor.horse_id) ?? []), factor])); return map; }, [factors]);
  const reviewsByLot = useMemo(() => { const map = new Map<string, AdminAuctionReview[]>(); reviews.forEach((review) => map.set(review.lot_id, [...(map.get(review.lot_id) ?? []), review])); return map; }, [reviews]);
  const reviewCountForLot = (lotId: string) => {
    const slots = new Set((reviewsByLot.get(lotId) ?? []).map((review) => review.slot));
    Object.keys(locallySavedReviewSlots)
      .filter((key) => key.startsWith(`${lotId}:`))
      .forEach((key) => slots.add(Number(key.slice(lotId.length + 1))));
    return slots.size;
  };
  const roundById = useMemo(() => new Map(rounds.map((round) => [round.id, round])), [rounds]);
  const [selectedLotId, setSelectedLotId] = useState<string | null>(null);
  const realtimeLot = snapshot?.currentLot ? lots.find((lot) => lot.id === snapshot.currentLot?.id) ?? null : null;
  const baseCurrentLot = (selectedLotId ? lots.find((lot) => lot.id === selectedLotId) ?? null : null)
    ?? realtimeLot
    ?? lots.find((lot) => ["OPEN_WAITING", "BIDDING", "CLOSED"].includes(lot.status))
    ?? lots.find((lot) => lot.status === "QUEUED")
    ?? lots.find((lot) => ["SOLD", "PASSED"].includes(lot.status))
    ?? null;
  const snapshotMatchesCurrentLot = Boolean(baseCurrentLot && snapshot?.currentLot?.id === baseCurrentLot.id);
  const currentLot = snapshotMatchesCurrentLot && baseCurrentLot && snapshot?.currentLot
    ? {
      ...baseCurrentLot,
      status: snapshot.currentLot.status,
      revealed_at: snapshot.currentLot.revealed_at,
      current_round_id: snapshot.currentRound?.id ?? null,
      current_price: snapshot.currentRound?.current_price ?? null,
      current_winner_owner_id: snapshot.currentRound?.current_winner_owner_id ?? null,
    }
    : baseCurrentLot;
  const existingHorseIds = useMemo(() => new Set(lots.map((lot) => lot.horse_id)), [lots]);
  const availableHorses = horses.filter((horse) => horse.life_stage === "FOAL" && horse.owner_id === null && !existingHorseIds.has(horse.id));

  async function executeRpc({ action, rpc, args, success }: Omit<PendingConfirmation, "message">) {
    setBusyAction(action);
    setNotice(null);
    const { error } = await getSupabase().rpc(rpc, args);
    setBusyAction(null);
    if (error) {
      setNotice(adminError(error.message));
      return;
    }
    setNotice(success);
    if (action === "rollback-confirm" && typeof args.p_rollback_request_id === "string") {
      // The broadcast snapshot reaches the room before the server component's
      // administrative list necessarily re-renders. Hide this completed
      // two-step card immediately; a later refresh remains the source of
      // truth for the request's final status.
      setCompletedRollbackRequestIds((current) => [...current, args.p_rollback_request_id as string]);
    }
    if (action.startsWith("review:") && typeof args.p_lot_id === "string" && typeof args.p_slot === "number") {
      setLocallySavedReviewSlots((current) => ({ ...current, [`${args.p_lot_id}:${args.p_slot}`]: true }));
    }
    if (action === "event-remove") {
      router.replace("/admin/public-auction");
      return;
    }
    refreshSnapshot();
    router.refresh();
  }

  function callRpc(action: string, rpc: string, args: Record<string, unknown>, success: string, confirmation?: string) {
    if (confirmation) {
      setPendingConfirmation({ action, rpc, args, success, message: confirmation });
      return;
    }
    void executeRpc({ action, rpc, args, success });
  }

  async function createLotForEvent() {
    const startingPrice = parseAuctionAmount(createLot.startingPrice);
    const evaluationValue = parseAuctionAmount(createLot.evaluationValue);
    const lotNumber = Number(createLot.lotNumber);
    if (!createLot.horseId || !Number.isInteger(lotNumber) || lotNumber < 1 || startingPrice === null || evaluationValue === null) {
      setNotice("请选择 Horse，并填写正整数 Lot 编号、起拍价与评价价值。金额可输入 1500万 或 15000000。");
      return;
    }
    callRpc("create-lot", "create_public_auction_lot", { p_event_id: event.id, p_horse_id: createLot.horseId, p_lot_number: lotNumber, p_starting_price: startingPrice.toString(), p_evaluation_value: evaluationValue.toString() }, "Lot 已创建；数据库已复核该 Horse 的庭先未成交资格。", "确认把该 Horse 加入本届公开拍卖？");
  }

  const persistedCurrentRound = currentLot?.current_round_id ? roundById.get(currentLot.current_round_id) ?? null : null;
  // The server-rendered management data is useful for the queue and audit
  // controls, while the active room must follow the same authoritative
  // snapshot as PLAYER clients.  Broadcasts therefore update price, winner
  // and bid history here without requiring a page navigation.
  const currentRound = snapshotMatchesCurrentLot && snapshot?.currentRound
    ? snapshot.currentRound
    : persistedCurrentRound;
  const currentBids = snapshotMatchesCurrentLot && snapshot?.currentRound && currentRound?.id === snapshot.currentRound.id
    ? snapshot.bids.map((bid) => ({
      id: bid.id,
      amount: bid.amount,
      accepted_at: bid.accepted_at,
      ownerName: bid.owner?.display_name ?? "Owner",
    }))
    : (currentRound
      ? bids
        .filter((bid) => bid.round_id === currentRound.id)
        .sort((left, right) => new Date(left.accepted_at).getTime() - new Date(right.accepted_at).getTime())
        .map((bid) => ({ ...bid, ownerName: ownerById.get(bid.owner_id) ?? "Owner" }))
      : []);
  const currentSettlement = currentLot && ["SOLD", "PASSED"].includes(currentLot.status)
    ? settlements.find((settlement) => settlement.round_id === currentRound?.id) ?? null
    : null;
  const pendingRollback = currentLot
    ? rollbackRequests.find((request) => request.lot_id === currentLot.id && request.status === "PENDING_CONFIRMATION" && !completedRollbackRequestIds.includes(request.id)) ?? null
    : null;

  return <main className="mx-auto w-full max-w-7xl px-6 py-8">
    <div className="flex flex-col gap-5 border-b border-stone-800 pb-6 lg:flex-row lg:items-start lg:justify-between"><div><p className="text-xs font-semibold tracking-[0.24em] text-amber-300">GM · PUBLIC AUCTION CONTROL</p><h1 className="mt-2 text-3xl font-semibold tracking-tight">{event.name}</h1><p className="mt-2 text-sm text-stone-400">WP {event.wp_year} · Event：{formatPublicAuctionStatus(event.status)} · 最小加价：{formatGameMoney(event.minimum_increment)}</p></div><div className="flex flex-wrap gap-2"><button className="rounded-lg border border-stone-600 px-3 py-2 text-sm text-stone-200 hover:border-amber-300" onClick={() => { refreshSnapshot(); router.refresh(); }} type="button">刷新现场状态</button>{event.status === "DRAFT" && <button className="admin-button" disabled={busyAction !== null} onClick={() => void callRpc("event-open", "set_public_auction_event_status", { p_event_id: event.id, p_status: "OPEN" }, "Event 已开放。现在可以展示第一匹资料。", "确认开放本届公开拍卖？") } type="button">开放 Event</button>}{event.status === "CLOSED" && <button className="admin-button" disabled={busyAction !== null} onClick={() => void callRpc("event-reopen", "set_public_auction_event_status", { p_event_id: event.id, p_status: "OPEN" }, "Event 已重新开放。", "确认重新开放 Event？") } type="button">重新开放 Event</button>}{event.status === "CLOSED" && <button className="rounded-lg border border-stone-600 px-3 py-2 text-sm text-stone-200 hover:border-amber-300" disabled={busyAction !== null} onClick={() => void callRpc("event-settle", "set_public_auction_event_status", { p_event_id: event.id, p_status: "SETTLED" }, "Event 已标记为已结算。", "确认将所有 Lot 都已最终完成的 Event 标记为已结算？") } type="button">结束 Event</button>}</div></div>
    <p className="mt-4 text-sm text-stone-400">现场 Realtime：{connectionState === "connected" ? "已连接" : "正在以数据库快照恢复同步"}。所有按钮都调用已部署的受控 RPC，前端不会直接修改业务表。</p>
    {notice && <p aria-live="polite" className="mt-4 rounded-lg border border-amber-300/30 bg-amber-300/5 p-4 text-sm text-amber-100">{notice}</p>}
    {pendingConfirmation && <section aria-live="polite" className="mt-4 rounded-xl border border-amber-300/50 bg-amber-300/10 p-4 text-sm text-amber-50"><p className="font-semibold">需要确认</p><p className="mt-1 leading-6">{pendingConfirmation.message}</p><div className="mt-3 flex flex-wrap gap-2"><button className="rounded-lg border border-stone-600 px-4 py-2 text-sm font-semibold text-stone-100 hover:border-stone-400" onClick={() => setPendingConfirmation(null)} type="button">取消</button><button className="admin-button" disabled={busyAction !== null} onClick={() => { const action = pendingConfirmation; setPendingConfirmation(null); void executeRpc(action); }} type="button">确认执行</button></div></section>}

    {event.status === "DRAFT" && <section className="mt-6 rounded-xl border border-stone-800 bg-stone-900 p-6"><h2 className="text-xl font-semibold text-amber-200">加入 Lot</h2><p className="mt-2 text-sm text-stone-400">候选清单仅作辅助；数据库会再次确认 Horse 是同 WP 年庭先未成交、未归属的 FOAL。</p><div className="mt-5 grid gap-3 lg:grid-cols-[minmax(0,1fr)_8rem_10rem_10rem_auto]"><select className="admin-input mt-0" onChange={(input) => setCreateLot((current) => ({ ...current, horseId: input.target.value }))} value={createLot.horseId}><option value="">选择候选 Horse</option>{availableHorses.map((horse) => <option key={horse.id} value={horse.id}>#{horse.horse_number} · {horse.translated_name || horse.foal_name}</option>)}</select><input className="admin-input mt-0" min="1" onChange={(input) => setCreateLot((current) => ({ ...current, lotNumber: input.target.value }))} placeholder="Lot 编号" type="number" value={createLot.lotNumber} /><input className="admin-input mt-0" onChange={(input) => setCreateLot((current) => ({ ...current, startingPrice: input.target.value }))} placeholder="起拍价" value={createLot.startingPrice} /><input className="admin-input mt-0" onChange={(input) => setCreateLot((current) => ({ ...current, evaluationValue: input.target.value }))} placeholder="评价价值" value={createLot.evaluationValue} /><button className="admin-button" disabled={busyAction !== null} onClick={() => void createLotForEvent()} type="button">创建 Lot</button></div></section>}

    {event.status === "DRAFT" && <details className="mt-6 rounded-xl border border-red-400/35 bg-red-400/5 p-6"><summary className="cursor-pointer text-xl font-semibold text-red-100">危险操作：移除草稿 Event</summary><p className="mt-3 text-sm leading-6 text-stone-300">仅草稿 Event 可以移除。所有未展示、未开始的 Lot、Round 与评价会一同移除，对应 Horse 可重新配置；每个 Lot 与 Event 都会留下审计记录。</p><label className="admin-label mt-4">移除原因<input className="admin-input" onChange={(input) => setDraftRemovalReasons((current) => ({ ...current, event: input.target.value }))} placeholder="必须填写移除原因" value={draftRemovalReasons.event} /></label><button className="mt-3 inline-flex items-center justify-center rounded-lg border border-red-400/60 px-4 py-2.5 text-sm font-semibold text-red-100 hover:bg-red-400/10 disabled:cursor-not-allowed disabled:opacity-60" disabled={busyAction !== null || !draftRemovalReasons.event.trim()} onClick={() => void callRpc("event-remove", "remove_public_auction_draft_event", { p_event_id: event.id, p_reason: draftRemovalReasons.event.trim() }, "草稿 Event 已移除。", "确认移除该草稿 Event 及其全部未开始 Lot？此操作不能通过普通页面撤销。")} type="button">移除草稿 Event</button></details>}

    <div className="mt-6 grid gap-6 xl:grid-cols-[minmax(0,1.35fr)_minmax(20rem,0.65fr)]">
      <section className="space-y-6">
        <section className="rounded-xl border border-amber-300/25 bg-stone-900 p-6"><p className="text-xs font-semibold tracking-[0.18em] text-amber-300">CURRENT LOT</p>{currentLot ? <><div className="mt-3 flex flex-col justify-between gap-4 sm:flex-row"><div><p className="font-mono text-sm text-stone-400">LOT {String(currentLot.lot_number).padStart(3, "0")}</p><h2 className="mt-1 text-2xl font-semibold">{horseById.get(currentLot.horse_id)?.translated_name || horseById.get(currentLot.horse_id)?.foal_name || "Horse"}</h2><p className="mt-2 text-sm text-stone-400">Lot：{formatPublicAuctionStatus(currentLot.status)} · Round：{currentRound ? formatPublicAuctionStatus(currentRound.status) : "—"}</p></div><dl className="grid grid-cols-2 gap-4 text-right text-sm"><div><dt className="text-stone-500">当前价</dt><dd className="mt-1 font-mono text-xl text-amber-200">{formatGameMoney(currentRound?.current_price)}</dd></div><div><dt className="text-stone-500">当前 Winner</dt><dd className="mt-1 text-stone-100">{currentRound?.current_winner_owner_id ? ownerById.get(currentRound.current_winner_owner_id) ?? "Owner" : "—"}</dd></div></dl></div>
          <div className="mt-6 flex flex-wrap gap-3">{currentLot.status === "QUEUED" && !currentLot.revealed_at && <button className="admin-button" disabled={busyAction !== null || reviewCountForLot(currentLot.id) !== 5 || event.status !== "OPEN"} onClick={() => void callRpc("reveal", "reveal_public_auction_lot", { p_lot_id: currentLot.id }, "该 Horse 与五份评价已公开展示，普通评价编辑已冻结。", "展示后所有 PLAYER 将立即看到该幼驹资料和评价，普通评价将无法再编辑。确认展示？")} type="button">展示本马</button>}{currentLot.revealed_at && currentLot.status === "QUEUED" && <button className="admin-button" disabled={busyAction !== null || event.status !== "OPEN"} onClick={() => void callRpc("open", "open_public_auction_lot", { p_lot_id: currentLot.id }, "竞价已开始，等待第一笔报价。", "确认开始竞价？Reveal 不会自动开始竞价。")} type="button">开始竞价</button>}{currentRound && ["OPEN_WAITING", "BIDDING"].includes(currentRound.status) && <button className="rounded-lg border border-amber-300/60 px-4 py-2.5 text-sm font-semibold text-amber-100 hover:bg-amber-300/10 disabled:cursor-not-allowed disabled:opacity-60" disabled={busyAction !== null} onClick={() => void callRpc("close", "close_public_auction_lot", { p_lot_id: currentLot.id, p_reason: null }, "服务器已将本轮关闭。", "确认尝试关闭当前 Lot？BIDDING 必须已经到达服务器 10 秒截止；无首笔报价的等待状态可由 GM 结束。")} type="button">关闭当前 Lot</button>}{currentLot.status === "CLOSED" && (currentRound?.current_winner_owner_id ? <button className="admin-button" disabled={busyAction !== null} onClick={() => void callRpc("settle-sold", "settle_public_auction_lot", { p_lot_id: currentLot.id, p_reason: null }, "成交已确认：Horse、扣款和公开结果均由数据库事务完成。", "确认按当前系统 Winner 和最终金额成交？")} type="button">确认成交</button> : <button className="rounded-lg border border-red-400/60 px-4 py-2.5 text-sm font-semibold text-red-100 hover:bg-red-400/10 disabled:cursor-not-allowed disabled:opacity-60" disabled={busyAction !== null} onClick={() => void callRpc("settle-pass", "settle_public_auction_pass", { p_lot_id: currentLot.id, p_reason: null }, "流拍已确认，Horse 已按受控流程进入 DISCARDED。", "确认流拍？确认后该 Horse 将进入 DISCARDED。")} type="button">确认流拍</button>)}{currentLot.status === "CLOSED" && !currentSettlement && <div className="w-full"><label className="admin-label">普通 Reopen 理由<input className="admin-input" id="reopen-reason" placeholder="必须填写 reopen_reason" /></label><button className="mt-3 rounded-lg border border-stone-600 px-4 py-2.5 text-sm font-semibold text-stone-100 hover:border-amber-300" disabled={busyAction !== null} onClick={() => { const input = document.getElementById("reopen-reason") as HTMLInputElement | null; const reason = input?.value.trim() ?? ""; if (!reason) { setNotice("普通 Reopen 必须填写 reopen_reason。"); return; } void callRpc("reopen", "reopen_public_auction_lot", { p_lot_id: currentLot.id, p_reopen_reason: reason }, "当前 Lot 已按原 Round 重新开放。", "确认按普通流程重新开放当前 Lot？") }} type="button">重新开放竞价</button></div>}</div>
          <div className="mt-4 text-sm text-stone-400">Factors：{factorsByHorse.get(currentLot.horse_id)?.map((factor) => `${factor.factor_kind} ${factor.factor_name}`).join(" · ") || "—"}</div>
          <div className="mt-6 rounded-lg border border-stone-800 bg-stone-950/60 p-4"><p className="font-semibold text-stone-200">当前 Round 公开 Bid 历史</p><div className="mt-3 max-h-56 overflow-y-auto text-sm">{currentBids.map((bid) => <div className="flex justify-between gap-4 border-b border-stone-800 py-2 last:border-0" key={bid.id}><span className="text-stone-400">{formatDateTime(bid.accepted_at)} · {bid.ownerName}</span><span className="font-mono text-amber-200">{formatGameMoney(bid.amount)}</span></div>)}{!currentBids.length && <p className="text-stone-500">本轮尚无 Bid。</p>}</div></div>
          {event.status === "DRAFT" && currentLot.status === "QUEUED" && !currentLot.revealed_at && <details className="mt-6 rounded-lg border border-red-400/30 bg-red-400/5 p-4"><summary className="cursor-pointer text-sm font-semibold text-red-200">危险操作：移除当前草稿 Lot</summary><p className="mt-3 text-sm leading-6 text-stone-300">仅未展示、未开始且没有 Bid、结算或回滚历史的 Lot 可以移除。相关评价与初始 Round 会一起移除，Horse 可重新配置；操作会被审计。</p><label className="admin-label mt-4">移除原因<input className="admin-input" onChange={(input) => setDraftRemovalReasons((current) => ({ ...current, lot: input.target.value }))} placeholder="必须填写移除原因" value={draftRemovalReasons.lot} /></label><button className="mt-3 inline-flex items-center justify-center rounded-lg border border-red-400/60 px-4 py-2.5 text-sm font-semibold text-red-100 hover:bg-red-400/10 disabled:cursor-not-allowed disabled:opacity-60" disabled={busyAction !== null || !draftRemovalReasons.lot.trim()} onClick={() => void callRpc("lot-remove", "remove_public_auction_draft_lot", { p_lot_id: currentLot.id, p_reason: draftRemovalReasons.lot.trim() }, "草稿 Lot 已移除，Horse 可以重新配置。", "确认移除当前草稿 Lot？此操作不能通过普通页面撤销。")} type="button">移除当前 Lot</button></details>}
        </> : <p className="mt-3 text-stone-400">尚未有可主持的当前 Lot。</p>}</section>

        {currentLot && <section className="rounded-xl border border-stone-800 bg-stone-900 p-6"><h2 className="text-xl font-semibold text-amber-200">五份评价准备</h2><p className="mt-2 text-sm text-stone-400">五项都完成后才能展示。展示之后由数据库冻结普通 Review 编辑。</p><div className="mt-5 grid gap-3">{[1, 2, 3, 4, 5].map((slot) => { const review = (reviewsByLot.get(currentLot.id) ?? []).find((item) => item.slot === slot); const key = `review:${currentLot.id}:${slot}`; return <ReviewEditor busy={busyAction === key} key={slot} lot={currentLot} review={review ? review : { id: "", lot_id: currentLot.id, slot, stars: 5, comment: "" }} onSave={(reviewSlot, stars, comment) => void callRpc(key, "upsert_public_auction_lot_review", { p_lot_id: currentLot.id, p_slot: reviewSlot, p_stars: stars, p_comment: comment.trim() }, `评价 ${reviewSlot} 已保存。`)} />; })}</div></section>}

        {currentLot && ["SOLD", "PASSED"].includes(currentLot.status) && <details className="rounded-xl border border-red-400/35 bg-red-400/5 p-6" open={Boolean(pendingRollback)}>
          <summary className="cursor-pointer text-xl font-semibold text-red-100">危险操作：Emergency Rollback</summary>
          <div className="mt-3">
            <p className="text-sm leading-6 text-stone-300">仅用于重大错误。原 Bid、Settlement 和资金流水不会被删除；系统会通过补偿与新 Round 恢复。原因、请求和补偿信息不会进入 PLAYER Snapshot。</p>
            {pendingRollback ? <div className="mt-5 rounded-lg border border-red-300/40 bg-stone-950/60 p-4"><p className="font-semibold text-red-100">第二阶段：严格确认</p><p className="mt-2 text-sm text-stone-300">输入以下文本才能执行：<code className="ml-1 rounded bg-stone-800 px-1.5 py-0.5 text-amber-200">{pendingRollback.expected_confirmation}</code></p><input className="admin-input" onChange={(input) => setRollbackConfirmations((values) => ({ ...values, [pendingRollback.id]: input.target.value }))} placeholder={pendingRollback.expected_confirmation} value={rollbackConfirmations[pendingRollback.id] ?? ""} /><button className="mt-3 inline-flex items-center justify-center rounded-lg border border-red-400/60 px-4 py-2.5 text-sm font-semibold text-red-100 hover:bg-red-400/10 disabled:cursor-not-allowed disabled:opacity-60" disabled={busyAction !== null || rollbackConfirmations[pendingRollback.id] !== pendingRollback.expected_confirmation} onClick={() => void callRpc("rollback-confirm", "confirm_public_auction_emergency_rollback", { p_rollback_request_id: pendingRollback.id, p_confirmation: rollbackConfirmations[pendingRollback.id] }, "紧急回滚已执行。旧 Round 已作废，当前 Lot 回到新 Round QUEUED。", "这是不可逆的受控补偿操作。确认执行紧急回滚？")} type="button">确认执行紧急回滚</button></div> : <div className="mt-5"><label className="admin-label">回滚原因<textarea className="admin-input min-h-24" onChange={(input) => setRollbackReasons((values) => ({ ...values, [currentLot.id]: input.target.value }))} placeholder="必须填写重大错误的具体原因" value={rollbackReasons[currentLot.id] ?? ""} /></label><button className="mt-3 inline-flex items-center justify-center rounded-lg border border-red-400/60 px-4 py-2.5 text-sm font-semibold text-red-100 hover:bg-red-400/10 disabled:cursor-not-allowed disabled:opacity-60" disabled={busyAction !== null || !(rollbackReasons[currentLot.id] ?? "").trim()} onClick={() => void callRpc("rollback-request", "request_public_auction_emergency_rollback", { p_lot_id: currentLot.id, p_reason: rollbackReasons[currentLot.id].trim() }, "回滚申请已建立。请在第二阶段输入严格确认文本。", "确认申请紧急回滚？这不会立即执行，但会写入内部审计记录。")} type="button">申请紧急回滚</button></div>}
          </div>
        </details>}
      </section>

      <aside className="rounded-xl border border-stone-800 bg-stone-900 p-5 xl:sticky xl:top-5 xl:max-h-[calc(100vh-3rem)] xl:overflow-y-auto"><h2 className="font-semibold text-amber-200">Lot 队列（GM 内部）</h2><div className="mt-4 space-y-2">{lots.map((lot) => { const horse = horseById.get(lot.horse_id); const reviewCount = reviewCountForLot(lot.id); const displayLot = lot.id === currentLot?.id ? currentLot : lot; return <button className={`w-full rounded-lg border p-3 text-left ${lot.id === currentLot?.id ? "border-amber-300/60 bg-amber-300/5" : "border-stone-800 bg-stone-950/50 hover:border-stone-600"}`} key={lot.id} onClick={() => setSelectedLotId(lot.id)} type="button"><div className="flex justify-between gap-3"><div><p className="font-mono text-xs text-stone-500">LOT {String(lot.lot_number).padStart(3, "0")}</p><p className="mt-1 text-sm font-medium text-stone-100">{horse?.translated_name || horse?.foal_name || "Horse"}</p></div><span className="text-xs text-stone-400">{formatPublicAuctionStatus(displayLot.status)}</span></div><p className="mt-2 text-xs text-stone-500">Review：{reviewCount}/5 · {displayLot.revealed_at ? "已展示" : "未展示"}</p></button>; })}{!lots.length && <p className="text-sm text-stone-500">尚无 Lot。</p>}</div></aside>
    </div>
  </main>;
}
