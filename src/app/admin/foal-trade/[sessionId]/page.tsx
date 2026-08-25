import Link from "next/link";
import { notFound } from "next/navigation";

import {
  createFoalTradeLot,
  removeFoalTradeDraftLot,
  removeFoalTradeDraftSession,
  replyToFoalTradeInquiry,
  settleFoalTradeLot,
  settleFoalTradeLotOverride,
  updateFoalTradeSessionSchedule,
  updateFoalTradeSessionStatus,
} from "@/app/admin/foal-trade/actions";
import { ActionForm } from "@/components/action-form";
import { GMPageHeader, GMSectionNav } from "@/components/gm-admin-ui";
import { Notice } from "@/components/notice";
import { StatusBadge } from "@/components/ui/primitives";
import { requireGM } from "@/lib/auth/session";
import {
  formatDateTime,
  formatFoalTradeLotStatus,
  formatFoalTradeInquiryStatus,
  formatFoalTradeSettlementStatus,
  formatFoalTradeSessionStatus,
  formatGameMoney,
  formatHorseSex,
  formatPedigreeFactorKind,
  formatSecretBidOfferStatus,
  toChinaDateInput,
  toChinaTimeInput,
} from "@/lib/format";

type PageProps = {
  params: Promise<{ sessionId: string }>;
  searchParams: Promise<{ notice?: string }>;
};

export const dynamic = "force-dynamic";

const scheduleStartTimes = ["09:00", "12:00", "18:00", "20:00", "21:00", "22:00"];
const scheduleDurations = [
  ["1", "1 小时"],
  ["3", "3 小时"],
  ["6", "6 小时"],
  ["12", "12 小时"],
  ["24", "1 天"],
  ["72", "3 天"],
  ["168", "7 天"],
] as const;

export default async function AdminFoalTradeDetailPage({ params, searchParams }: PageProps) {
  const [{ sessionId }, { notice }, { supabase }] = await Promise.all([params, searchParams, requireGM()]);
  const { data: session } = await supabase
    .from("foal_trade_sessions")
    .select("id, wp_year, starts_at, ends_at, status")
    .eq("id", sessionId)
    .maybeSingle();

  if (!session) {
    notFound();
  }

  const [{ data: lots }, { data: inquiries }, { data: offers }, { data: settlements }, { data: candidateHorses }, { data: allLotHorses }] = await Promise.all([
    supabase
      .from("foal_trade_lots")
      .select("id, horse_id, minimum_price, status, created_at")
      .eq("session_id", session.id)
      .order("created_at"),
    supabase
      .from("foal_trade_inquiries")
      .select("id, lot_id, owner_id, gm_comment, status, requested_at, answered_at")
      .eq("session_id", session.id)
      .order("requested_at"),
    supabase
      .from("secret_bid_offers")
      .select("id, lot_id, owner_id, amount, status, priority_at")
      .eq("session_id", session.id)
      .order("amount", { ascending: false }),
    supabase
      .from("foal_trade_settlements")
      .select("id, lot_id, status, winner_owner_id, amount, is_override, override_reason, confirmed_at")
      .eq("session_id", session.id),
    supabase
      .from("horses")
      .select("id, horse_number, foal_name, translated_name, sex, coat_color, sire_name, sire_line, broodmare_sire_name")
      .eq("birth_year", session.wp_year)
      .is("owner_id", null)
      .eq("life_stage", "FOAL")
      .order("horse_number"),
    supabase.from("foal_trade_lots").select("horse_id"),
  ]);

  const lotHorseIds = (lots ?? []).map((lot) => lot.horse_id);
  const [{ data: lotHorses }, { data: factors }, { data: owners }] = await Promise.all([
    lotHorseIds.length
      ? supabase
          .from("horses")
          .select("id, horse_number, foal_name, translated_name, sex, coat_color, sire_name, sire_line, broodmare_sire_name, owner_id, life_stage")
          .in("id", lotHorseIds)
      : Promise.resolve({ data: [] }),
    lotHorseIds.length
      ? supabase.from("horse_factors").select("horse_id, factor_kind, factor_name").in("horse_id", lotHorseIds).order("created_at")
      : Promise.resolve({ data: [] }),
    supabase.from("owners").select("id, display_name").order("display_name"),
  ]);

  const usedHorseIds = new Set((allLotHorses ?? []).map((lot) => lot.horse_id));
  const availableHorses = (candidateHorses ?? []).filter((horse) => !usedHorseIds.has(horse.id));
  const horseById = new Map((lotHorses ?? []).map((horse) => [horse.id, horse]));
  const ownerNameById = new Map((owners ?? []).map((owner) => [owner.id, owner.display_name]));
  const factorsByHorse = new Map<string, { factor_kind: string; factor_name: string }[]>();
  for (const factor of factors ?? []) {
    const current = factorsByHorse.get(factor.horse_id) ?? [];
    current.push(factor);
    factorsByHorse.set(factor.horse_id, current);
  }
  const inquiriesByLot = new Map<string, typeof inquiries>();
  for (const inquiry of inquiries ?? []) {
    const current = inquiriesByLot.get(inquiry.lot_id) ?? [];
    current.push(inquiry);
    inquiriesByLot.set(inquiry.lot_id, current);
  }
  const offersByLot = new Map<string, typeof offers>();
  for (const offer of offers ?? []) {
    const current = offersByLot.get(offer.lot_id) ?? [];
    current.push(offer);
    offersByLot.set(offer.lot_id, current);
  }
  const settlementByLot = new Map((settlements ?? []).map((settlement) => [settlement.lot_id, settlement]));
  const canConfigure = session.status === "DRAFT" && new Date(session.starts_at) > new Date();
  const activeDeadlinePassed = new Date(session.ends_at) <= new Date();
  const currentStartTime = toChinaTimeInput(session.starts_at);
  const selectedStartTime = scheduleStartTimes.includes(currentStartTime) ? currentStartTime : "";
  const exactDurationHours = (new Date(session.ends_at).getTime() - new Date(session.starts_at).getTime()) / (60 * 60 * 1000);
  const selectedDuration = Number.isInteger(exactDurationHours) && scheduleDurations.some(([value]) => value === String(exactDurationHours))
    ? String(exactDurationHours)
    : "";

  return (
    <main className="page-wrap">
      <nav className="mb-5 text-sm text-[#68736c]" aria-label="面包屑"><Link className="hover:text-[#173f35]" href="/admin/foal-trade">庭先交易</Link><span className="mx-2">/</span><span>WP {session.wp_year}</span></nav>
      <GMPageHeader action={<StatusBadge tone={session.status === "OPEN" ? "success" : session.status === "DRAFT" ? "neutral" : "warning"}>{formatFoalTradeSessionStatus(session.status)}</StatusBadge>} description={<>报价、询问和结算的最终合法性由数据库服务器时间与 RPC 决定。<span className="mt-2 block">{formatDateTime(session.starts_at)} — {formatDateTime(session.ends_at)}</span></>} eyebrow={`WP ${session.wp_year} · AUGUST FOAL TRADE`} title="庭先届次详情" />
      <Notice message={notice} />
      <GMSectionNav items={[{ href: "#overview", label: "届次概览" }, { count: lots?.length ?? 0, href: "#lots", label: "标的" }, { count: inquiries?.filter((item) => item.status === "REQUESTED").length ?? 0, href: "#lots", label: "询问" }, { href: "#lots", label: "报价结算" }, { href: "#danger", label: "危险操作" }]} />

      <section className="scroll-mt-32 mt-8 grid gap-6 xl:grid-cols-2" id="overview">
        <div className="rounded-xl border border-stone-800 bg-stone-900 p-6">
          <h2 className="text-xl font-semibold text-amber-200">届次状态</h2>
          <ActionForm action={updateFoalTradeSessionStatus.bind(null, session.id)} className="mt-5 flex flex-col gap-3 sm:flex-row" pendingLabel="正在保存…" submitLabel="保存状态">
            <select className="admin-input mt-0 flex-1" defaultValue={session.status} name="status">
              <option value="DRAFT">草稿</option><option value="OPEN">开放中</option><option value="CLOSED">已关闭</option><option value="REVIEWING">结算审核中</option>
            </select>
          </ActionForm>
          <p className="mt-3 text-xs leading-5 text-stone-500">“已结算”状态会在所有标的结算完成后自动设定，不在此手动选择。</p>
        </div>

        {canConfigure && (
          <div className="rounded-xl border border-stone-800 bg-stone-900 p-6">
            <h2 className="text-xl font-semibold text-amber-200">草稿时间配置</h2>
            <p className="mt-2 text-sm leading-6 text-stone-400">按中国标准时间设置开始日期和时刻，再选择报价时长。系统会自动计算并保存截止时间。</p>
            <ActionForm action={updateFoalTradeSessionSchedule.bind(null, session.id)} className="mt-5 grid gap-4 sm:grid-cols-3" pendingLabel="正在保存…" submitLabel="保存时间">
              <label className="admin-label">开始日期（中国标准时间）<input className="admin-input" defaultValue={toChinaDateInput(session.starts_at)} name="start_date" required type="date" /></label>
              <label className="admin-label">开始时刻<select className="admin-input" defaultValue={selectedStartTime} name="start_time" required><option disabled value="">{selectedStartTime ? "选择时刻" : `当前为 ${currentStartTime}；请选择预设`}</option>{scheduleStartTimes.map((time) => <option key={time} value={time}>{time}</option>)}</select></label>
              <label className="admin-label">报价时长<select className="admin-input" defaultValue={selectedDuration} name="duration_hours" required><option disabled value="">{selectedDuration ? "选择时长" : "请选择 1 小时至 7 天的预设"}</option>{scheduleDurations.map(([value, label]) => <option key={value} value={value}>{label}</option>)}</select></label>
            </ActionForm>
          </div>
        )}
      </section>

      {canConfigure && (
        <section className="mt-6 rounded-xl border border-stone-800 bg-stone-900 p-6">
          <h2 className="text-xl font-semibold text-amber-200">加入标的</h2>
          <p className="mt-2 text-sm text-stone-400">仅列出本届出生批次、未归属、仍处于幼驹阶段且尚未参加任何庭先的马匹。数据库会再次验证这些条件。</p>
          <ActionForm action={createFoalTradeLot.bind(null, session.id)} className="mt-5 grid gap-4 lg:grid-cols-[minmax(0,1fr)_14rem_auto]" pendingLabel="正在创建…" submitLabel="创建标的">
            <select className="admin-input mt-0" name="horse_id" required><option value="">选择符合条件的马匹</option>{availableHorses.map((horse) => <option key={horse.id} value={horse.id}>#{horse.horse_number} · {horse.translated_name || horse.foal_name}</option>)}</select>
            <input className="admin-input mt-0" min="0" name="minimum_price" placeholder="最低报价" required step="1" type="number" />
          </ActionForm>
          {!availableHorses.length && <p className="mt-3 text-sm text-stone-500">没有可加入的马匹。</p>}
        </section>
      )}

      {canConfigure && (
        <section className="scroll-mt-32 mt-6 rounded-xl border border-red-400/35 bg-red-400/5 p-6" id="danger">
          <h2 className="text-xl font-semibold text-red-100">危险操作：移除草稿届次</h2>
          <p className="mt-2 text-sm leading-6 text-stone-300">仅未开始的草稿届次可移除。该操作会移除其中所有未开始标的，使马匹可重新配置；询问、报价、结算或已开始届次绝不能通过此处删除。每项移除都会保留审计记录。</p>
          <ActionForm action={removeFoalTradeDraftSession.bind(null, session.id)} className="mt-5 grid gap-3 sm:grid-cols-[minmax(0,1fr)_auto]" confirmation="确认移除本草稿届次及其全部未开始标的？此操作不能通过普通页面撤销。" pendingLabel="正在移除…" submitLabel="移除草稿届次" variant="danger">
            <input className="admin-input mt-0" name="removal_reason" placeholder="必须填写移除原因" required />
          </ActionForm>
        </section>
      )}

      <section className="scroll-mt-32 mt-8 grid gap-6" id="lots">
        {(lots ?? []).map((lot) => {
          const horse = horseById.get(lot.horse_id);
          const lotInquiries = inquiriesByLot.get(lot.id) ?? [];
          const lotOffers = offersByLot.get(lot.id) ?? [];
          const activeOffers = lotOffers
            .filter((offer) => offer.status === "ACTIVE")
            .sort((left, right) => Number(right.amount) - Number(left.amount) || new Date(left.priority_at).getTime() - new Date(right.priority_at).getTime() || left.id.localeCompare(right.id));
          const recommended = activeOffers[0];
          const settlement = settlementByLot.get(lot.id);
          const horseFactors = factorsByHorse.get(lot.horse_id) ?? [];

          return (
            <article className="rounded-xl border border-stone-800 bg-stone-900 p-6" key={lot.id}>
              <div className="flex flex-col justify-between gap-5 lg:flex-row">
                <div>
                  <p className="font-mono text-sm font-semibold text-amber-300">标的 · 马匹 #{horse?.horse_number ?? "—"}</p>
                  <h2 className="mt-2 text-2xl font-semibold">{horse?.translated_name || horse?.foal_name || "马匹资料不可用"}</h2>
                  <p className="mt-2 text-sm text-stone-400">{horse ? `${formatHorseSex(horse.sex)} / ${horse.coat_color} · 父：${horse.sire_name} · 父系：${horse.sire_line} · 母父：${horse.broodmare_sire_name}` : "—"}</p>
                  <p className="mt-2 text-sm text-stone-400">血统因子：{horseFactors.map((factor) => `${formatPedigreeFactorKind(factor.factor_kind)} ${factor.factor_name}`).join(" · ") || "—"}</p>
                </div>
                <dl className="grid grid-cols-2 gap-4 text-sm lg:text-right"><div><dt className="text-stone-500">最低报价</dt><dd className="mt-1 font-mono text-amber-200">{formatGameMoney(lot.minimum_price)}</dd></div><div><dt className="text-stone-500">标的状态</dt><dd className="mt-1 text-stone-200">{formatFoalTradeLotStatus(lot.status)}</dd></div></dl>
              </div>

              {canConfigure && (
                <details className="mt-5 rounded-lg border border-red-400/30 bg-red-400/5 p-4">
                  <summary className="cursor-pointer text-sm font-semibold text-red-200">危险操作：移除此草稿标的</summary>
                  <p className="mt-3 text-sm leading-6 text-stone-300">仅未开始、没有询问、报价或结算历史的标的可以移除。马匹会重新成为可配置候选，移除原因会写入审计。</p>
                  <ActionForm action={removeFoalTradeDraftLot.bind(null, session.id, lot.id)} className="mt-4 grid gap-3 sm:grid-cols-[minmax(0,1fr)_auto]" confirmation="确认移除这个草稿标的？此操作不能通过普通页面撤销。" pendingLabel="正在移除…" submitLabel="移除标的" variant="danger">
                    <input className="admin-input mt-0" name="removal_reason" placeholder="必须填写移除原因" required />
                  </ActionForm>
                </details>
              )}

              {settlement ? (
                <div className="mt-6 rounded-lg border border-emerald-400/30 bg-emerald-400/5 p-4 text-sm"><p className="font-semibold text-emerald-200">已结算：{formatFoalTradeSettlementStatus(settlement.status)}</p>{settlement.status === "SOLD" && <p className="mt-2 text-stone-200">马主：{ownerNameById.get(settlement.winner_owner_id ?? "") ?? "—"} · 价格：{formatGameMoney(settlement.amount)}{settlement.is_override ? " · GM 例外裁定" : ""}</p>}<p className="mt-2 text-xs text-stone-500">确认：{formatDateTime(settlement.confirmed_at)}</p></div>
              ) : (
                <div className="mt-6 grid gap-6 border-t border-stone-800 pt-6 xl:grid-cols-2">
                  <section>
                    <h3 className="font-semibold text-amber-200">GM 询问（内部）</h3>
                    <div className="mt-3 grid gap-3">
                      {lotInquiries.map((inquiry) => (
                        <div className="rounded-lg border border-stone-800 bg-stone-950/60 p-4" key={inquiry.id}>
                          <p className="text-sm font-medium text-stone-100">{ownerNameById.get(inquiry.owner_id) ?? "未知马主"}</p>
                          <p className="mt-1 text-xs text-stone-500">请求：{formatDateTime(inquiry.requested_at)} · {formatFoalTradeInquiryStatus(inquiry.status)}</p>
                          <ActionForm action={replyToFoalTradeInquiry.bind(null, session.id, inquiry.id)} className="mt-3 flex flex-col gap-3" pendingLabel="正在保存…" submitLabel="保存 GM 回复" variant="secondary">
                            <textarea className="admin-input mt-0 min-h-24" defaultValue={inquiry.gm_comment ?? ""} name="gm_comment" required />
                          </ActionForm>
                          {inquiry.answered_at && <p className="mt-2 text-xs text-stone-500">上次回复：{formatDateTime(inquiry.answered_at)}</p>}
                        </div>
                      ))}
                      {!lotInquiries.length && <p className="text-sm text-stone-500">尚无询问。</p>}
                    </div>
                  </section>

                  <section>
                    <h3 className="font-semibold text-amber-200">秘密报价（内部）</h3>
                    <div className="mt-3 overflow-hidden rounded-lg border border-stone-800"><table className="w-full text-left text-sm"><thead className="bg-stone-950 text-stone-500"><tr><th className="px-3 py-2">马主</th><th className="px-3 py-2">金额</th><th className="px-3 py-2">优先时间</th><th className="px-3 py-2">状态</th></tr></thead><tbody className="divide-y divide-stone-800">{lotOffers.map((offer) => <tr key={offer.id}><td className="px-3 py-2 text-stone-200">{ownerNameById.get(offer.owner_id) ?? "未知马主"}</td><td className="px-3 py-2 font-mono text-amber-200">{formatGameMoney(offer.amount)}</td><td className="px-3 py-2 text-stone-400">{formatDateTime(offer.priority_at)}</td><td className="px-3 py-2 text-stone-400">{formatSecretBidOfferStatus(offer.status)}</td></tr>)}{!lotOffers.length && <tr><td className="px-3 py-4 text-stone-500" colSpan={4}>尚无秘密报价。</td></tr>}</tbody></table></div>
                    <div className="mt-4 rounded-lg border border-amber-300/20 bg-amber-300/5 p-4 text-sm"><p className="font-semibold text-amber-100">系统推荐</p>{recommended ? <p className="mt-2 text-stone-200">{ownerNameById.get(recommended.owner_id) ?? "未知马主"} · <span className="font-mono text-amber-200">{formatGameMoney(recommended.amount)}</span><span className="block mt-1 text-xs text-stone-500">报价优先时间：{formatDateTime(recommended.priority_at)}</span></p> : <p className="mt-2 text-stone-400">没有有效报价；正常结算会记录为未成交。</p>}</div>
                    <div className="mt-4 flex flex-col gap-3">
                      <ActionForm action={settleFoalTradeLot.bind(null, session.id, lot.id)} confirmation="确认按系统推荐结果结算？数据库会再次校验截止时间、资金与幂等性。" pendingLabel="正在结算…" submitLabel={recommended ? "按系统结果成交" : "确认未成交结算"} />
                      {!activeDeadlinePassed && <p className="text-xs text-amber-100">页面提示：当前尚未到显示截止时间；结算 RPC 将以数据库服务器时间拒绝提前结算。</p>}
                      {recommended && activeOffers.length > 1 && (
                        <details className="rounded-lg border border-red-400/30 bg-red-400/5 p-4"><summary className="cursor-pointer text-sm font-semibold text-red-200">更多操作：GM 例外裁定</summary><p className="mt-3 text-sm leading-6 text-stone-300">这是异常路径：必须选择非系统推荐的有效报价，并填写会写入审计记录的理由。</p><ActionForm action={settleFoalTradeLotOverride.bind(null, session.id, lot.id)} className="mt-4 grid gap-3" confirmation="确认执行 GM 例外裁定？此操作会按所选有效报价结算并记录审计。" pendingLabel="正在裁定…" submitLabel="确认例外裁定" variant="danger"><select className="admin-input mt-0" name="selected_offer_id" required><option value="">选择另一条有效报价</option>{activeOffers.filter((offer) => offer.id !== recommended.id).map((offer) => <option key={offer.id} value={offer.id}>{ownerNameById.get(offer.owner_id) ?? "未知马主"} · {formatGameMoney(offer.amount)} · {formatDateTime(offer.priority_at)}</option>)}</select><textarea className="admin-input mt-0 min-h-24" name="override_reason" placeholder="必须填写例外裁定理由" required /></ActionForm></details>
                      )}
                    </div>
                  </section>
                </div>
              )}
            </article>
          );
        })}
        {!lots?.length && <p className="text-stone-500">本届尚未加入标的。</p>}
      </section>
    </main>
  );
}
