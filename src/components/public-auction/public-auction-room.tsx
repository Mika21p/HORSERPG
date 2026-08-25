"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";

import { formatDateTime, formatGameMoney, formatHorseSex } from "@/lib/format";
import {
  auctionRoundDeadline,
  formatAuctionInput,
  formatPublicAuctionStatus,
  getBidSuggestion,
  isAuctionAmountIncrement,
  parseAuctionAmount,
  publicAuctionConnectionLabel,
} from "@/lib/public-auction/ui";
import { usePublicAuctionRealtime } from "@/lib/public-auction/use-public-auction-realtime";
import { createClient } from "@/lib/supabase/client";

type Funds = {
  account_funds: number | string;
  foal_trade_frozen_funds: number | string;
  public_auction_frozen_funds: number | string;
  total_frozen_funds: number | string;
  available_funds: number | string;
};

type BidRequest = {
  amount: bigint;
  requestId: string;
  roundId: string;
};

type PublicAuctionRoomProps = {
  eventId: string;
  viewerOwnerId: string | null;
  viewerRole: "PLAYER" | "GM" | null;
};

function AuctionCountdown({ deadline, mode }: { deadline: string | null; mode: "BIDDING" | "OPEN_WAITING" | null }) {
  const [now, setNow] = useState(() => Date.now());

  useEffect(() => {
    if (!deadline) {
      return;
    }
    const interval = window.setInterval(() => setNow(Date.now()), 100);
    return () => window.clearInterval(interval);
  }, [deadline]);

  if (!deadline || !mode) {
    return null;
  }

  const remaining = Math.max(0, new Date(deadline).getTime() - now);
  if (mode === "OPEN_WAITING") {
    return (
      <div className="rounded-xl border border-amber-300/30 bg-amber-300/5 p-4">
        <p className="text-sm font-semibold text-amber-100">等待第一笔报价</p>
        <p className="mt-1 text-sm text-stone-300">无首笔报价时，等待窗口将在 {formatDateTime(deadline)} 结束。</p>
      </div>
    );
  }

  return (
    <div className="rounded-xl border border-red-300/50 bg-red-400/10 p-4 text-center">
      <p className="text-xs font-semibold tracking-[0.18em] text-red-100">本轮倒计时</p>
      <p className="mt-1 font-mono text-5xl font-semibold tabular-nums text-red-100">{(remaining / 1000).toFixed(1)}</p>
      {remaining === 0 && <p className="mt-2 text-sm text-red-100">等待服务器确认截单状态</p>}
    </div>
  );
}

function Stars({ value }: { value: number }) {
  return <span aria-label={`${value} 星`} className="font-mono tracking-[0.12em] text-amber-300">{"★".repeat(value)}{"☆".repeat(5 - value)}</span>;
}

function safeAuctionError(message: string | undefined) {
  const normalized = message?.toLowerCase() ?? "";
  if (normalized.includes("auction round has changed")) {
    return "拍卖轮次已经变化，请确认当前状态后重新报价。";
  }
  if (normalized.includes("deadline") || normalized.includes("not accepting bids")) {
    return "报价未被服务器接受，竞价已经结束。";
  }
  if (normalized.includes("current winner") || normalized.includes("highest")) {
    return "你当前是最高出价者，不能继续抬价。";
  }
  if (normalized.includes("available funds") || normalized.includes("sufficient funds")) {
    return "可用资金不足，报价未被服务器接受。";
  }
  if (normalized.includes("increment") || normalized.includes("starting price") || normalized.includes("100000")) {
    return "报价必须满足起拍价和最小加价规则，并为 10 万整数倍。";
  }
  if (normalized.includes("request")) {
    return "本次报价请求无法接受。请刷新状态后确认是否需要重新报价。";
  }
  return "报价未被服务器接受。请刷新当前拍卖状态后重试。";
}

export function PublicAuctionRoom({ eventId, viewerOwnerId, viewerRole }: PublicAuctionRoomProps) {
  const { connectionState, isRefreshing, refreshSnapshot, snapshot, snapshotError } = usePublicAuctionRealtime(eventId);
  const supabaseRef = useRef<ReturnType<typeof createClient> | null>(null);
  const [amountInput, setAmountInput] = useState("");
  const [bidRequest, setBidRequest] = useState<BidRequest | null>(null);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [notice, setNotice] = useState<string | null>(null);
  const [funds, setFunds] = useState<Funds | null>(null);
  const [fundsError, setFundsError] = useState<string | null>(null);
  const [isRefreshingFunds, setIsRefreshingFunds] = useState(false);

  const getSupabase = useCallback(() => {
    if (!supabaseRef.current) {
      supabaseRef.current = createClient();
    }
    return supabaseRef.current;
  }, []);

  const refreshFunds = useCallback(async () => {
    if (viewerRole !== "PLAYER") {
      return;
    }
    setIsRefreshingFunds(true);
    const { data, error } = await getSupabase().rpc("get_current_owner_financial_summary");
    if (error || !data?.[0]) {
      setFundsError("资金汇总暂时无法刷新。报价合法性仍由数据库 RPC 最终裁定。");
      setIsRefreshingFunds(false);
      return;
    }
    setFunds(data[0] as Funds);
    setFundsError(null);
    setIsRefreshingFunds(false);
  }, [getSupabase, viewerRole]);

  const currentRound = snapshot?.currentRound ?? null;
  const currentLot = snapshot?.currentLot ?? null;
  const suggestion = useMemo(() => getBidSuggestion(snapshot), [snapshot]);
  const fundsRefreshKey = `${currentRound?.id ?? ""}:${currentRound?.current_winner_owner_id ?? ""}:${snapshot?.settlement?.status ?? ""}:${snapshot?.settlement?.confirmed_at ?? ""}`;
  const deadline = auctionRoundDeadline(snapshot);
  const [clock, setClock] = useState(() => Date.now());
  useEffect(() => {
    if (!deadline) {
      return;
    }
    const interval = window.setInterval(() => setClock(Date.now()), 100);
    return () => window.clearInterval(interval);
  }, [deadline]);
  const deadlinePassed = deadline ? new Date(deadline).getTime() <= clock : false;
  const isCurrentWinner = Boolean(viewerOwnerId && currentRound?.current_winner_owner_id === viewerOwnerId);
  const auctionAcceptingBids = snapshot?.event.status === "OPEN"
    && Boolean(currentLot?.revealed_at)
    && Boolean(currentRound && ["OPEN_WAITING", "BIDDING"].includes(currentRound.status));
  const canBid = viewerRole === "PLAYER"
    && Boolean(viewerOwnerId)
    && auctionAcceptingBids
    && !isCurrentWinner
    && connectionState === "connected"
    && !deadlinePassed;

  useEffect(() => {
    const timer = window.setTimeout(() => void refreshFunds(), 0);
    return () => window.clearTimeout(timer);
  }, [fundsRefreshKey, refreshFunds]);

  const submitBid = useCallback(async (request: BidRequest) => {
    if (!currentLot || !currentRound) {
      return;
    }

    setNotice(null);
    setIsSubmitting(true);
    const { error } = await getSupabase().rpc("submit_public_auction_bid", {
      p_lot_id: currentLot.id,
      p_expected_round_id: request.roundId,
      p_amount: request.amount.toString(),
      p_request_id: request.requestId,
    });

    if (error) {
      setIsSubmitting(false);
      if (error.message.toLowerCase().includes("auction round has changed")) {
        refreshSnapshot();
      }
      const transportFailure = !error.code || /fetch|network|timeout|offline/i.test(error.message);
      if (!transportFailure) {
        setBidRequest(null);
      }
      if (transportFailure) {
        setNotice("网络请求未确认。可以重试同一请求；系统会使用相同 request_id 保持幂等。");
        return;
      }
      setNotice(safeAuctionError(error.message));
      return;
    }

    setIsSubmitting(false);
    setBidRequest(null);
    setNotice("报价已被服务器接受。");
    refreshSnapshot();
    void refreshFunds();
  }, [currentLot, currentRound, getSupabase, refreshFunds, refreshSnapshot]);

  function startBid() {
    if (!currentRound || !canBid) {
      return;
    }
    const amount = parseAuctionAmount(amountInput || formatAuctionInput(suggestion));
    if (amount === null || !isAuctionAmountIncrement(amount)) {
      setNotice("请输入 10 万整数倍金额，例如 1500万 或 15000000。");
      return;
    }
    const request = { amount, requestId: crypto.randomUUID(), roundId: currentRound.id };
    setBidRequest(request);
    void submitBid(request);
  }

  function addQuickAmount(increment: bigint) {
    const current = parseAuctionAmount(amountInput || formatAuctionInput(suggestion)) ?? suggestion ?? BigInt(0);
    setAmountInput((current + increment).toString());
  }

  const factors = currentLot?.horse?.factors ?? [];
  const sireFactors = factors.filter((factor) => factor.factor_kind === "SIRE");
  const mareFactors = factors.filter((factor) => factor.factor_kind === "MARE");

  return (
    <div className="auction-stage min-h-[calc(100vh-4rem)]">
    <main className="mx-auto w-full max-w-[1320px] px-4 py-6 sm:px-6 sm:py-10 xl:px-8">
      <section className="rounded-2xl border border-stone-800 bg-stone-900 p-5 shadow-2xl shadow-black/20 sm:p-7">
        <div className="flex flex-col gap-4 lg:flex-row lg:items-start lg:justify-between">
          <div>
            <p className="text-xs font-semibold tracking-[0.24em] text-amber-300">公开拍卖现场</p>
            <h1 className="mt-2 text-3xl font-semibold tracking-tight">{snapshot ? `${snapshot.event.wp_year} 年公开拍卖会` : "年末公开拍卖会"}</h1>
            {snapshot && <p className="mt-2 text-sm text-stone-400">拍卖状态：{formatPublicAuctionStatus(snapshot.event.status)}</p>}
          </div>
          <div className={`rounded-lg border px-4 py-3 text-sm ${connectionState === "connected" ? "border-emerald-300/40 bg-emerald-300/5 text-emerald-100" : "border-amber-300/40 bg-amber-300/5 text-amber-100"}`}>
            <p className="font-semibold">{publicAuctionConnectionLabel(connectionState)}</p>
            {(connectionState === "disconnected" || connectionState === "error") && <p className="mt-1 text-xs">实时连接只负责通知；已显示的数据库快照会继续保留。</p>}
            <button className="mt-2 text-xs underline underline-offset-4 hover:text-amber-50" disabled={isRefreshing} onClick={refreshSnapshot} type="button">{isRefreshing ? "正在刷新…" : "立即刷新状态"}</button>
          </div>
        </div>
        {snapshotError && <p className="mt-5 rounded-lg border border-amber-300/30 bg-amber-300/5 p-3 text-sm text-amber-100">{snapshotError}</p>}
      </section>

      {!snapshot ? (
        <section className="mt-6 rounded-2xl border border-stone-800 bg-stone-900 p-8 text-center text-stone-400">正在读取数据库权威快照……</section>
      ) : !currentLot ? (
        <section className="mt-6 rounded-2xl border border-stone-800 bg-stone-900 p-8 text-center"><h2 className="text-xl font-semibold text-stone-100">等待 GM 展示下一匹幼驹</h2><p className="mt-3 text-sm text-stone-400">后续标的不会在此页面提前显示。</p></section>
      ) : (
        <div className="mt-6 grid gap-6 xl:grid-cols-[minmax(0,1.45fr)_minmax(22rem,0.85fr)]">
          <div className="space-y-6">
            <section className="rounded-2xl border border-stone-800 bg-stone-900 p-5 sm:p-7">
              <div className="flex flex-wrap items-start justify-between gap-4">
                <div className="min-w-0"><p className="font-mono text-sm font-semibold text-amber-300">标的 {String(currentLot.lot_number).padStart(3, "0")}</p><h2 className="mt-2 break-words text-3xl font-semibold">{currentLot.horse?.translated_name || currentLot.horse?.foal_name || "马匹资料暂不可用"}</h2><p className="mt-2 text-sm text-stone-400">马匹 #{currentLot.horse?.horse_number ?? "—"}</p></div>
                <div className="rounded-xl bg-stone-950 px-4 py-3 text-right"><p className="text-xs text-stone-500">评价价值</p><p className="mt-1 font-mono text-xl font-semibold text-amber-200">{formatGameMoney(currentLot.evaluation_value)}</p><p className="mt-2 text-xs text-stone-500">起拍价</p><p className="mt-1 font-mono text-lg text-stone-100">{formatGameMoney(currentLot.starting_price)}</p></div>
              </div>
              {currentLot.horse && <div className="mt-6 grid gap-3 border-t border-stone-800 pt-5 text-sm text-stone-300 sm:grid-cols-2"><p>性别：{formatHorseSex(currentLot.horse.sex)}</p><p>毛色：{currentLot.horse.coat_color}</p><p>父：{currentLot.horse.sire_name}</p><p>父系：{currentLot.horse.sire_line}</p><p>母父：{currentLot.horse.broodmare_sire_name}</p><p>父系因子：{sireFactors.map((factor) => factor.factor_name).join(" · ") || "—"}</p><p className="sm:col-span-2">母系因子：{mareFactors.map((factor) => factor.factor_name).join(" · ") || "—"}</p></div>}
            </section>

            <section className="rounded-2xl border border-stone-800 bg-stone-900 p-5 sm:p-7"><h2 className="text-xl font-semibold text-amber-200">五份评价</h2><div className="mt-5 grid gap-3">{[1, 2, 3, 4, 5].map((slot) => { const review = currentLot.reviews.find((item) => item.slot === slot); return <div className="rounded-lg border border-stone-800 bg-stone-950/50 p-4" key={slot}><div className="flex items-center justify-between gap-3"><span className="text-xs font-semibold text-stone-500">评价 {slot}</span>{review ? <Stars value={review.stars} /> : <span className="text-xs text-stone-500">未提供</span>}</div><p className="mt-2 text-sm leading-6 text-stone-200">{review?.comment ?? "—"}</p></div>; })}</div></section>

            <section className="rounded-2xl border border-stone-800 bg-stone-900 p-5 sm:p-7"><h2 className="text-xl font-semibold text-amber-200">本轮公开报价</h2><div className="mt-5 max-h-80 overflow-y-auto rounded-lg border border-stone-800"><table className="w-full table-fixed text-left text-sm"><thead className="sticky top-0 bg-stone-950 text-stone-500"><tr><th className="w-[31%] px-3 py-3">时间</th><th className="w-[35%] px-3 py-3">马主</th><th className="w-[34%] px-3 py-3 text-right">报价</th></tr></thead><tbody className="divide-y divide-stone-800">{snapshot.bids.map((bid) => <tr className={bid.owner?.id === currentRound?.current_winner_owner_id ? "bg-amber-300/5" : undefined} key={bid.id}><td className="break-words px-3 py-3 text-stone-400">{formatDateTime(bid.accepted_at)}</td><td className="break-words px-3 py-3 text-stone-200">{bid.owner?.display_name ?? "未知马主"}</td><td className="break-all px-3 py-3 text-right font-mono text-amber-200">{formatGameMoney(bid.amount)}</td></tr>)}{!snapshot.bids.length && <tr><td className="px-3 py-6 text-center text-stone-500" colSpan={3}>本轮尚无公开报价。</td></tr>}</tbody></table></div></section>
          </div>

          <aside className="space-y-6 xl:sticky xl:top-5 xl:self-start">
            <section className="rounded-2xl border border-amber-300/30 bg-stone-900 p-5"><p className="text-xs font-semibold tracking-[0.18em] text-stone-500">当前价格</p><p className="mt-2 break-all font-mono text-3xl font-semibold tracking-tight text-amber-200 sm:text-4xl">{formatGameMoney(currentRound?.current_price ?? currentLot.starting_price)}</p><p className="mt-3 text-sm text-stone-400">当前最高出价者</p><p className="mt-1 break-words text-xl font-semibold text-stone-100">{snapshot.bids.find((bid) => bid.owner?.id === currentRound?.current_winner_owner_id)?.owner?.display_name ?? (currentRound?.current_winner_owner_id ? "当前领先马主" : "等待首笔报价")}</p><div className="mt-5"><AuctionCountdown deadline={deadline} mode={currentRound?.status === "BIDDING" ? "BIDDING" : currentRound?.status === "OPEN_WAITING" ? "OPEN_WAITING" : null} /></div></section>

            {viewerRole === "PLAYER" && <section className="rounded-2xl border border-stone-800 bg-stone-900 p-5"><div className="flex items-center justify-between gap-3"><h2 className="font-semibold text-amber-200">我的资金</h2><button className="text-xs text-stone-400 underline underline-offset-4 hover:text-amber-200" disabled={isRefreshingFunds} onClick={() => void refreshFunds()} type="button">{isRefreshingFunds ? "刷新中…" : "刷新"}</button></div>{funds ? <dl className="mt-4 grid gap-3 text-sm"><div className="flex justify-between gap-4"><dt className="text-stone-400">账户资金</dt><dd className="font-mono text-stone-100">{formatGameMoney(funds.account_funds)}</dd></div><div className="flex justify-between gap-4"><dt className="text-stone-400">庭先冻结</dt><dd className="font-mono text-stone-100">{formatGameMoney(funds.foal_trade_frozen_funds)}</dd></div><div className="flex justify-between gap-4"><dt className="text-stone-400">公开拍卖冻结</dt><dd className="font-mono text-stone-100">{formatGameMoney(funds.public_auction_frozen_funds)}</dd></div><div className="flex justify-between gap-4 border-t border-stone-800 pt-3"><dt className="font-semibold text-stone-300">总冻结</dt><dd className="font-mono text-stone-100">{formatGameMoney(funds.total_frozen_funds)}</dd></div><div className="flex justify-between gap-4"><dt className="font-semibold text-amber-100">可用资金</dt><dd className="font-mono font-semibold text-amber-200">{formatGameMoney(funds.available_funds)}</dd></div></dl> : <p className="mt-4 text-sm text-stone-500">正在读取你的资金汇总……</p>}{fundsError && <p className="mt-3 text-xs text-amber-100">{fundsError}</p>}</section>}

            <section className="rounded-2xl border border-stone-800 bg-stone-900 p-5"><h2 className="font-semibold text-amber-200">公开报价</h2>{isCurrentWinner ? <p className="mt-3 rounded-lg border border-emerald-300/30 bg-emerald-300/5 p-3 text-sm text-emerald-100">你当前是最高出价者</p> : viewerRole !== "PLAYER" ? <p className="mt-3 text-sm text-stone-400">GM 可观察公开竞价；只有绑定马主的玩家可以报价。</p> : !auctionAcceptingBids ? <p className="mt-3 text-sm text-stone-400">当前标的暂未开放竞价。</p> : connectionState !== "connected" ? <p className="mt-3 rounded-lg border border-amber-300/30 bg-amber-300/5 p-3 text-sm text-amber-100">实时连接暂时异常，请等待状态同步后再报价。</p> : <><label className="mt-4 block text-sm text-stone-300">报价金额（支持 1500万 或 15000000）<input className="admin-input font-mono" disabled={isSubmitting} inputMode="numeric" onChange={(event) => setAmountInput(event.target.value)} placeholder={suggestion === null ? "输入报价" : `建议 ${formatGameMoney(suggestion)}`} value={amountInput} /></label><div className="mt-3 grid grid-cols-2 gap-2">{[BigInt(100_000), BigInt(500_000), BigInt(1_000_000), BigInt(5_000_000)].map((increment) => <button className="rounded-lg border border-stone-700 px-3 py-2 text-sm text-stone-200 hover:border-amber-300 hover:text-amber-200 disabled:opacity-60" disabled={isSubmitting} key={increment.toString()} onClick={() => addQuickAmount(increment)} type="button">+{formatGameMoney(increment)}</button>)}</div><button className="admin-button mt-4 w-full" disabled={!canBid || isSubmitting} onClick={() => bidRequest ? void submitBid(bidRequest) : startBid()} type="button">{isSubmitting ? "提交中…" : bidRequest ? "重试同一请求" : "提交报价"}</button><p className="mt-3 text-xs leading-5 text-stone-500">建议金额：{suggestion === null ? "—" : formatGameMoney(suggestion)}。本地倒计时仅供参考，数据库裁定才是最终结果。</p></>}</section>

            {notice && <p aria-live="polite" className="rounded-xl border border-amber-300/30 bg-amber-300/5 p-4 text-sm text-amber-100">{notice}</p>}
            {snapshot.settlement && <section className={`rounded-2xl border p-5 ${snapshot.settlement.status === "SOLD" ? "border-emerald-300/40 bg-emerald-300/5" : "border-stone-700 bg-stone-900"}`}><p className="text-xs font-semibold tracking-[0.18em] text-stone-400">最终结果</p><h2 className="mt-2 text-2xl font-semibold">{snapshot.settlement.status === "SOLD" ? "成交" : "流拍"}</h2>{snapshot.settlement.status === "SOLD" && <><p className="mt-3 text-sm text-stone-400">成交马主</p><p className="mt-1 break-words font-semibold text-stone-100">{snapshot.bids.find((bid) => bid.owner?.id === snapshot.settlement?.winner_owner_id)?.owner?.display_name ?? "—"}</p><p className="mt-3 text-sm text-stone-400">成交价</p><p className="mt-1 break-all font-mono text-2xl text-amber-200">{formatGameMoney(snapshot.settlement.amount)}</p></>}<p className="mt-4 text-xs text-stone-500">确认时间：{formatDateTime(snapshot.settlement.confirmed_at)}</p></section>}
          </aside>
        </div>
      )}
    </main>
    </div>
  );
}
