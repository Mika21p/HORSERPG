import Link from "next/link";
import { notFound } from "next/navigation";

import { createTradeInquiry, submitSecretBid, withdrawSecretBid } from "@/app/foal-trade/actions";
import { ActionForm } from "@/components/action-form";
import { AppShell } from "@/components/app-shell";
import { Notice } from "@/components/notice";
import { requireUser } from "@/lib/auth/session";
import {
  formatDateTime,
  formatFoalTradeLotStatus,
  formatFoalTradeSessionStatus,
  formatGameMoney,
  formatHorseSex,
  formatSecretBidOfferStatus,
} from "@/lib/format";

type PageProps = {
  params: Promise<{ sessionId: string }>;
  searchParams: Promise<{ notice?: string }>;
};

type Funds = {
  account_funds: bigint | number | string;
  foal_trade_frozen_funds: bigint | number | string;
  available_funds: bigint | number | string;
};

export const dynamic = "force-dynamic";

export default async function FoalTradeSessionPage({ params, searchParams }: PageProps) {
  const [{ sessionId }, { notice }, { supabase, user, profile }] = await Promise.all([
    params,
    searchParams,
    requireUser(),
  ]);
  const { data: session } = await supabase
    .from("foal_trade_sessions")
    .select("id, wp_year, starts_at, ends_at, status")
    .eq("id", sessionId)
    .maybeSingle();

  if (!session || (profile?.role !== "GM" && session.status === "DRAFT")) {
    notFound();
  }

  const { data: lots } = await supabase
    .from("foal_trade_lots")
    .select("id, horse_id, minimum_price, status")
    .eq("session_id", session.id)
    .order("created_at");
  const horseIds = (lots ?? []).map((lot) => lot.horse_id);

  const [{ data: horses }, { data: factors }, { data: publicSettlements }] = await Promise.all([
    horseIds.length
      ? supabase
          .from("horses")
          .select("id, horse_number, foal_name, translated_name, sex, coat_color, sire_name, sire_line, broodmare_sire_name")
          .in("id", horseIds)
      : Promise.resolve({ data: [] }),
    horseIds.length
      ? supabase.from("horse_factors").select("horse_id, factor_kind, factor_name").in("horse_id", horseIds).order("created_at")
      : Promise.resolve({ data: [] }),
    supabase
      .from("foal_trade_public_settlements")
      .select("lot_id, horse_id, status, winner_owner_id, amount, confirmed_at")
      .eq("session_id", session.id),
  ]);

  const isPlayer = profile?.role === "PLAYER" && Boolean(profile.owner_id);
  const [{ data: ownInquiries }, { data: ownOffers }, { data: rawFunds, error: fundsError }] = isPlayer
    ? await Promise.all([
        supabase
          .from("foal_trade_inquiries")
          .select("id, lot_id, gm_comment, status, requested_at, answered_at")
          .eq("session_id", session.id),
        supabase
          .from("secret_bid_offers")
          .select("id, lot_id, amount, status, priority_at")
          .eq("session_id", session.id),
        supabase.rpc("get_current_owner_funds"),
      ])
    : [{ data: [] }, { data: [] }, { data: null, error: null }];

  const funds = (Array.isArray(rawFunds) ? rawFunds[0] : rawFunds) as Funds | null;
  const winnerOwnerIds = (publicSettlements ?? [])
    .map((settlement) => settlement.winner_owner_id)
    .filter((ownerId): ownerId is string => Boolean(ownerId));
  const { data: winners } = winnerOwnerIds.length
    ? await supabase.from("owners").select("id, display_name").in("id", winnerOwnerIds)
    : { data: [] };

  const horseById = new Map((horses ?? []).map((horse) => [horse.id, horse]));
  const factorsByHorse = new Map<string, { factor_kind: string; factor_name: string }[]>();
  for (const factor of factors ?? []) {
    const current = factorsByHorse.get(factor.horse_id) ?? [];
    current.push(factor);
    factorsByHorse.set(factor.horse_id, current);
  }
  const inquiry = ownInquiries?.[0] ?? null;
  const offerByLotId = new Map((ownOffers ?? []).map((offer) => [offer.lot_id, offer]));
  const settlementByLotId = new Map((publicSettlements ?? []).map((settlement) => [settlement.lot_id, settlement]));
  const winnerNameById = new Map((winners ?? []).map((owner) => [owner.id, owner.display_name]));
  const inquiryHorse = inquiry ? horseById.get((lots ?? []).find((lot) => lot.id === inquiry.lot_id)?.horse_id ?? "") : null;
  // This is only a presentation guard. The bidding RPC remains the final
  // authority and uses database server time to reject any late request.
  const canShowActions = isPlayer && session.status === "OPEN" && new Date(session.ends_at) > new Date();

  return (
    <AppShell email={user.email} isGM={profile?.role === "GM"}>
      <main className="mx-auto w-full max-w-6xl px-6 py-10">
        <Link className="text-sm text-amber-200 hover:text-amber-100" href="/foal-trade">← 庭先届次列表</Link>
        <section className="mt-5 rounded-2xl border border-stone-800 bg-stone-900 p-6 sm:p-8">
          <div className="flex flex-col justify-between gap-5 sm:flex-row sm:items-start">
            <div>
              <p className="text-sm font-semibold tracking-[0.18em] text-amber-300">WP {session.wp_year} · AUGUST FOAL TRADE</p>
              <h1 className="mt-3 text-3xl font-semibold">庭先取引</h1>
              <p className="mt-3 text-stone-400">状态：{formatFoalTradeSessionStatus(session.status)}。现实截止时间以数据库服务器裁定，页面时间仅供参考。</p>
            </div>
            <dl className="grid gap-3 text-sm sm:text-right">
              <div><dt className="text-stone-500">开始（中国标准时间）</dt><dd className="mt-1 text-stone-200">{formatDateTime(session.starts_at)}</dd></div>
              <div><dt className="text-stone-500">截止（中国标准时间）</dt><dd className="mt-1 font-medium text-amber-200">{formatDateTime(session.ends_at)}</dd></div>
            </dl>
          </div>
        </section>
        <Notice message={notice} />

        {isPlayer && (
          <section className="mt-6 grid gap-4 md:grid-cols-3">
            <div className="rounded-xl border border-stone-800 bg-stone-900 p-5"><p className="text-sm text-stone-500">账户资金</p><p className="mt-2 font-mono text-xl text-stone-100">{funds ? formatGameMoney(funds.account_funds) : "暂不可用"}</p></div>
            <div className="rounded-xl border border-stone-800 bg-stone-900 p-5"><p className="text-sm text-stone-500">庭先冻结资金</p><p className="mt-2 font-mono text-xl text-amber-200">{funds ? formatGameMoney(funds.foal_trade_frozen_funds) : "暂不可用"}</p></div>
            <div className="rounded-xl border border-stone-800 bg-stone-900 p-5"><p className="text-sm text-stone-500">可用资金</p><p className="mt-2 font-mono text-xl text-stone-100">{funds ? formatGameMoney(funds.available_funds) : "暂不可用"}</p></div>
            {fundsError && <p className="text-sm text-red-200 md:col-span-3">资金汇总暂时无法读取，请稍后刷新重试。</p>}
          </section>
        )}

        {isPlayer && (
          <section className="mt-8 rounded-xl border border-stone-800 bg-stone-900 p-6">
            <h2 className="text-xl font-semibold text-amber-200">本届 GM 询问机会</h2>
            {inquiry ? (
              <div className="mt-4 rounded-lg border border-stone-800 bg-stone-950/60 p-4 text-sm">
                <p className="font-medium text-stone-100">已询问：{inquiryHorse ? `马匹 #${inquiryHorse.horse_number} · ${inquiryHorse.translated_name || inquiryHorse.foal_name}` : "已记录的标的"}</p>
                <p className="mt-2 text-stone-400">{inquiry.status === "ANSWERED" && inquiry.gm_comment ? inquiry.gm_comment : "等待 GM 回复"}</p>
              </div>
            ) : (
              <p className="mt-3 text-sm text-stone-400">本届尚未使用。每届只能询问一匹幼驹，提交后不能改成其他马匹。</p>
            )}
          </section>
        )}

        <section className="mt-8 grid gap-5">
          {(lots ?? []).map((lot) => {
            const horse = horseById.get(lot.horse_id);
            const horseFactors = factorsByHorse.get(lot.horse_id) ?? [];
            const sireFactors = horseFactors.filter((factor) => factor.factor_kind === "SIRE");
            const mareFactors = horseFactors.filter((factor) => factor.factor_kind === "MARE");
            const ownOffer = offerByLotId.get(lot.id);
            const settlement = settlementByLotId.get(lot.id);
            const isInquiryLot = inquiry?.lot_id === lot.id;

            return (
              <article className="rounded-xl border border-stone-800 bg-stone-900 p-6" key={lot.id}>
                <div className="flex flex-col justify-between gap-5 lg:flex-row">
                  <div className="min-w-0 flex-1">
                    <div className="flex flex-wrap items-center gap-3">
                      <p className="font-mono text-sm font-semibold tracking-wide text-amber-300">马匹 #{horse?.horse_number ?? "—"}</p>
                      <span className="rounded-full border border-stone-700 px-3 py-1 text-xs text-stone-300">{formatFoalTradeLotStatus(lot.status)}</span>
                    </div>
                    <h2 className="mt-3 text-2xl font-semibold text-stone-100">{horse?.translated_name || horse?.foal_name || "马匹资料不可用"}</h2>
                    <dl className="mt-5 grid gap-4 text-sm sm:grid-cols-2 lg:grid-cols-3">
                      <div><dt className="text-stone-500">性别 / 毛色</dt><dd className="mt-1 text-stone-200">{horse ? `${formatHorseSex(horse.sex)} / ${horse.coat_color}` : "—"}</dd></div>
                      <div><dt className="text-stone-500">父 / 父系</dt><dd className="mt-1 text-stone-200">{horse ? `${horse.sire_name} / ${horse.sire_line}` : "—"}</dd></div>
                      <div><dt className="text-stone-500">母父</dt><dd className="mt-1 text-stone-200">{horse?.broodmare_sire_name ?? "—"}</dd></div>
                      <div><dt className="text-stone-500">父系因子</dt><dd className="mt-1 text-stone-200">{sireFactors.map((factor) => factor.factor_name).join("、") || "—"}</dd></div>
                      <div><dt className="text-stone-500">母系因子</dt><dd className="mt-1 text-stone-200">{mareFactors.map((factor) => factor.factor_name).join("、") || "—"}</dd></div>
                      <div><dt className="text-stone-500">最低报价</dt><dd className="mt-1 font-mono font-semibold text-amber-200">{formatGameMoney(lot.minimum_price)}</dd></div>
                    </dl>
                  </div>

                  {settlement && (
                    <aside className="w-full rounded-lg border border-emerald-400/30 bg-emerald-400/5 p-4 text-sm lg:max-w-xs">
                      <p className="font-semibold text-emerald-200">公开结算结果</p>
                      {settlement.status === "SOLD" ? (
                        <><p className="mt-3 text-stone-400">成交马主</p><p className="mt-1 text-stone-100">{winnerNameById.get(settlement.winner_owner_id ?? "") ?? "已确认马主"}</p><p className="mt-3 text-stone-400">成交价格</p><p className="mt-1 font-mono text-emerald-100">{formatGameMoney(settlement.amount)}</p></>
                      ) : <p className="mt-3 text-stone-300">本标的未成交。</p>}
                      <p className="mt-3 text-xs text-stone-500">确认：{formatDateTime(settlement.confirmed_at)}</p>
                    </aside>
                  )}
                </div>

                {isPlayer && !settlement && (
                  <div className="mt-6 grid gap-5 border-t border-stone-800 pt-6 lg:grid-cols-2">
                    <section>
                      <h3 className="font-semibold text-stone-100">GM 询问</h3>
                      {isInquiryLot ? <p className="mt-2 text-sm text-amber-100">此马就是你的本届询问对象。</p> : inquiry ? <p className="mt-2 text-sm text-stone-500">本届询问机会已使用。</p> : canShowActions ? (
                        <ActionForm
                          action={createTradeInquiry.bind(null, session.id, lot.id)}
                          className="mt-3"
                          confirmation="每届庭先只能询问一匹幼驹，确认后不能改成其他马。确认询问此马？"
                          pendingLabel="正在提交…"
                          submitLabel="询问此马"
                          variant="secondary"
                        />
                      ) : <p className="mt-2 text-sm text-stone-500">当前状态不能提交询问。</p>}
                    </section>

                    <section>
                      <h3 className="font-semibold text-stone-100">你的秘密报价</h3>
                      {ownOffer?.status === "ACTIVE" ? (
                        <div className="mt-2">
                          <p className="text-sm text-stone-400">你的当前报价：<span className="font-mono text-amber-200">{formatGameMoney(ownOffer.amount)}</span></p>
                          {canShowActions && (
                            <div className="mt-3 flex flex-col gap-3 sm:flex-row">
                              <ActionForm action={submitSecretBid.bind(null, session.id, lot.id)} className="flex flex-1 gap-2" pendingLabel="正在保存…" submitLabel="保存修改">
                                <input aria-label="新的秘密报价" className="admin-input mt-0 min-w-0" defaultValue={String(ownOffer.amount)} min={String(lot.minimum_price)} name="amount" required step="1" type="number" />
                              </ActionForm>
                              <ActionForm action={withdrawSecretBid.bind(null, session.id, lot.id)} confirmation="确认撤回这笔秘密报价？对应冻结资金会释放。" pendingLabel="正在撤回…" submitLabel="撤回报价" variant="danger" />
                            </div>
                          )}
                        </div>
                      ) : canShowActions ? (
                        <ActionForm action={submitSecretBid.bind(null, session.id, lot.id)} className="mt-3 flex flex-col gap-3 sm:flex-row" pendingLabel="正在提交…" submitLabel={ownOffer?.status === "WITHDRAWN" ? "重新报价" : "提交秘密报价"}>
                          <input aria-label="秘密报价金额" className="admin-input mt-0 min-w-0 flex-1" min={String(lot.minimum_price)} name="amount" placeholder={`最低 ${formatGameMoney(lot.minimum_price)}`} required step="1" type="number" />
                        </ActionForm>
                      ) : <p className="mt-2 text-sm text-stone-500">{ownOffer?.status === "WITHDRAWN" ? "你的报价已撤回。" : ownOffer ? `你的报价状态：${formatSecretBidOfferStatus(ownOffer.status)}` : "你的报价：尚未报价"}</p>}
                    </section>
                  </div>
                )}
              </article>
            );
          })}
          {!lots?.length && <p className="text-stone-500">本届尚未配置公开标的。</p>}
        </section>
      </main>
    </AppShell>
  );
}
