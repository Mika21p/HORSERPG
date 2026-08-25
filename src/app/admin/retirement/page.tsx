import Link from "next/link";

import {
  confirmHorseRetirementRequest,
  createGmRetirementRequest,
  rejectHorseRetirementRequest,
} from "@/app/admin/retirement/actions";
import { ActionForm } from "@/components/action-form";
import { GMPageHeader, GMSectionNav } from "@/components/gm-admin-ui";
import { Notice } from "@/components/notice";
import { StatusBadge } from "@/components/ui/primitives";
import { requireGM } from "@/lib/auth/session";
import {
  formatDateTime,
  formatGameMoney,
  formatHorseLifeStage,
  formatHorseName,
  formatHorseRetirementRequestKind,
  formatHorseRetirementRequestStatus,
  formatPrizeReceivableLedgerEntryKind,
  formatWpTime,
} from "@/lib/format";

type PageProps = { searchParams: Promise<{ notice?: string }> };

type PrizeReceivable = {
  id: string;
  horse_id: string;
  owner_id: string;
  amount: string | number | bigint;
  status: string;
};

type LedgerEntry = {
  id: string;
  prize_receivable_id: string;
  retirement_request_id: string;
  entry_kind: string;
  amount_delta: string | number | bigint;
  reason: string | null;
  created_at: string;
};

type ConfirmedEntry = {
  id: string;
  horse_id: string;
  wp_year: number;
  wp_month: number;
  wp_week: number;
  race_label: string | null;
  race_kind: string;
};

function sumMoney(rows: Array<{ amount: string | number | bigint }>) {
  return rows.reduce((total, row) => total + BigInt(row.amount), BigInt(0));
}

function requestStatusClass(status: string) {
  if (status === "PENDING") return "border-amber-300/40 bg-amber-300/10 text-amber-100";
  if (status === "CONFIRMED") return "border-emerald-400/40 bg-emerald-400/10 text-emerald-100";
  if (status === "REJECTED") return "border-red-400/40 bg-red-400/10 text-red-100";
  return "border-stone-700 bg-stone-800 text-stone-300";
}

function wpOrder(year: number, month: number, week: number) {
  return year * 100 + month * 10 + week;
}

function isFutureEntry(entry: ConfirmedEntry, gameState: { current_wp_year: number; current_wp_month: number; current_wp_week: number } | null) {
  if (!gameState) return true;
  return wpOrder(entry.wp_year, entry.wp_month, entry.wp_week) > wpOrder(gameState.current_wp_year, gameState.current_wp_month, gameState.current_wp_week);
}

export const dynamic = "force-dynamic";

export default async function AdminRetirementPage({ searchParams }: PageProps) {
  const [{ supabase }, { notice }] = await Promise.all([requireGM(), searchParams]);
  const [
    { data: gameState, error: gameStateError },
    { data: requests, error: requestError },
    { data: horses, error: horseError },
    { data: owners, error: ownerError },
    { data: confirmedEntries, error: entryError },
    { data: receivables, error: receivableError },
    { data: ledgerEntries, error: ledgerError },
    { data: results, error: resultError },
    { data: actualRaces, error: actualRaceError },
  ] = await Promise.all([
    supabase.from("game_state").select("current_wp_year, current_wp_month, current_wp_week").maybeSingle(),
    supabase.from("horse_retirement_requests").select("id, horse_id, owner_id, request_kind, status, player_note, gm_reason, requested_at, reviewed_at, withdrawn_at, completed_at").order("requested_at", { ascending: false }),
    supabase.from("horses").select("id, horse_number, foal_name, translated_name, birth_year, owner_id, life_stage").order("horse_number"),
    supabase.from("owners").select("id, display_name").order("display_name"),
    supabase.from("confirmed_race_entries").select("id, horse_id, wp_year, wp_month, wp_week, race_kind, race_label").order("wp_year").order("wp_month").order("wp_week"),
    supabase.from("prize_receivables").select("id, horse_id, owner_id, amount, status").order("created_at", { ascending: false }),
    supabase.from("prize_receivable_ledger_entries").select("id, prize_receivable_id, retirement_request_id, entry_kind, amount_delta, reason, created_at").order("created_at", { ascending: false }),
    supabase.from("race_results").select("horse_id, actual_race_id, status, finish_position"),
    supabase.from("actual_races").select("id, grade"),
  ]);

  const dataError = gameStateError || requestError || horseError || ownerError || entryError || receivableError || ledgerError || resultError || actualRaceError;
  const horseById = new Map((horses ?? []).map((horse) => [horse.id, horse]));
  const ownerNameById = new Map((owners ?? []).map((owner) => [owner.id, owner.display_name]));
  const actualRaceById = new Map((actualRaces ?? []).map((race) => [race.id, race]));
  const g1WinsByHorseId = new Map<string, number>();
  for (const result of results ?? []) {
    if (result.status === "CONFIRMED" && result.finish_position === 1 && actualRaceById.get(result.actual_race_id)?.grade === "G1") {
      g1WinsByHorseId.set(result.horse_id, (g1WinsByHorseId.get(result.horse_id) ?? 0) + 1);
    }
  }

  const entriesByHorseId = new Map<string, ConfirmedEntry[]>();
  for (const entry of (confirmedEntries ?? []) as ConfirmedEntry[]) {
    entriesByHorseId.set(entry.horse_id, [...(entriesByHorseId.get(entry.horse_id) ?? []), entry]);
  }
  const pendingReceivablesByHorseId = new Map<string, PrizeReceivable[]>();
  for (const receivable of (receivables ?? []) as PrizeReceivable[]) {
    if (receivable.status === "PENDING") {
      pendingReceivablesByHorseId.set(receivable.horse_id, [...(pendingReceivablesByHorseId.get(receivable.horse_id) ?? []), receivable]);
    }
  }
  const receivableById = new Map(((receivables ?? []) as PrizeReceivable[]).map((receivable) => [receivable.id, receivable]));
  const requestById = new Map((requests ?? []).map((request) => [request.id, request]));
  const pendingRequests = (requests ?? []).filter((request) => request.status === "PENDING");
  const historyRequests = (requests ?? []).filter((request) => request.status !== "PENDING");
  const eligibleForceHorses = (horses ?? []).filter((horse) => horse.owner_id && horse.life_stage === "ACTIVE");

  return (
    <main className="page-wrap">
      <GMPageHeader action={<StatusBadge tone="warning">{gameState ? formatWpTime(gameState.current_wp_year, gameState.current_wp_month, gameState.current_wp_week) : "时间未初始化"}</StatusBadge>} description="退役确认是高风险、不可逆的受控流程：它会将马匹设为已退役，并在同一事务中释放所有待释放奖金。未来已确认赛程必须先按既有流程处理。" eyebrow="退役与奖金释放" title="退役与奖金结算" />

      <Notice message={notice} />
      {dataError && <p className="mt-5 rounded-xl border border-red-400/40 bg-red-400/5 p-4 text-sm leading-6 text-red-100">部分退役或奖金结算资料暂时无法读取。请刷新页面；页面不会显示数据库内部错误。</p>}
      <GMSectionNav items={[{ count: pendingRequests.length, href: "#pending", label: "待处理" }, { href: "#forced", label: "强制退役" }, { href: "#prizes", label: "奖金摘要" }, { count: historyRequests.length, href: "#history", label: "历史记录" }]} />

      <section className="mt-8 grid gap-6 xl:grid-cols-[minmax(19rem,0.8fr)_minmax(0,1.2fr)]">
        <section className="scroll-mt-32 h-fit rounded-xl border border-stone-800 bg-stone-900 p-6" id="forced">
          <h2 className="text-xl font-semibold text-amber-200">创建强制退役申请</h2>
          <p className="mt-2 text-sm leading-6 text-stone-400">仅限已有马主且当前现役的马匹。G1 九胜按当前有效赛果计数；WP 寿命裁定必须填写原因。创建后仍要单独确认退役与奖金结算。</p>
          <ActionForm action={createGmRetirementRequest} className="mt-5 space-y-4" confirmation="确认创建强制退役申请吗？马匹会进入退役处理中，但不会立刻退役或释放奖金。" pendingLabel="正在创建…" submitLabel="创建强制退役申请">
            <label className="admin-label">马匹
              <select className="admin-input" defaultValue="" name="horse_id" required>
                <option disabled value="">选择现役马匹</option>
                {eligibleForceHorses.map((horse) => <option key={horse.id} value={horse.id}>{formatHorseName(horse)} · #{horse.horse_number} · 马主：{ownerNameById.get(horse.owner_id ?? "") ?? "—"} · 当前 G1 {g1WinsByHorseId.get(horse.id) ?? 0} 胜</option>)}
              </select>
            </label>
            <label className="admin-label">强制类型
              <select className="admin-input" defaultValue="G1_LIMIT" name="request_kind">
                <option value="G1_LIMIT">G1 九胜退役（当前有效 G1 冠军须至少 9 场）</option>
                <option value="WP_LIFESPAN">WP 寿命裁定</option>
              </select>
            </label>
            <label className="admin-label">GM 原因
              <textarea className="admin-input min-h-24" name="gm_reason" placeholder="WP 寿命裁定为必填；G1 九胜可选补充说明" />
            </label>
          </ActionForm>
          {!eligibleForceHorses.length && <p className="mt-5 rounded-lg border border-stone-800 bg-stone-950/60 p-4 text-sm text-stone-500">当前没有可用于强制退役申请的已归属现役马匹。</p>}
        </section>

        <section className="scroll-mt-32" id="pending">
          <div className="flex items-end justify-between gap-4"><div><h2 className="text-xl font-semibold text-amber-200">等待处理的退役申请</h2><p className="mt-2 text-sm text-stone-400">确认前核对马匹、马主、未来赛程与每笔奖金应收的历史马主。数据库会在最终确认时再次锁定并验证全部事实。</p></div><span className="font-mono text-sm text-stone-500">{pendingRequests.length} 条</span></div>
          <div className="mt-5 space-y-5">
            {pendingRequests.map((request) => {
              const horse = horseById.get(request.horse_id);
              const futureEntries = (entriesByHorseId.get(request.horse_id) ?? []).filter((entry) => isFutureEntry(entry, gameState));
              const pendingPrizes = pendingReceivablesByHorseId.get(request.horse_id) ?? [];
              const prizeByOwner = new Map<string, PrizeReceivable[]>();
              for (const prize of pendingPrizes) prizeByOwner.set(prize.owner_id, [...(prizeByOwner.get(prize.owner_id) ?? []), prize]);
              const reject = rejectHorseRetirementRequest.bind(null, request.horse_id, request.id);
              const confirm = confirmHorseRetirementRequest.bind(null, request.horse_id, request.id);
              return (
                <article className="rounded-xl border border-stone-800 bg-stone-900 p-5 sm:p-6" key={request.id}>
                  <div className="flex flex-col gap-4 lg:flex-row lg:items-start lg:justify-between">
                    <div>
                      <Link className="text-xl font-semibold text-stone-100 hover:text-amber-100" href={`/horses/${request.horse_id}`}>{formatHorseName(horse)}</Link>
                      <p className="mt-2 text-sm text-stone-400">马匹 #{horse?.horse_number ?? "—"} · {horse ? `${gameState ? gameState.current_wp_year - horse.birth_year : "—"} 岁 · ${formatHorseLifeStage(horse.life_stage)}` : "资料不可用"} · 当前马主：{ownerNameById.get(request.owner_id) ?? "—"}</p>
                    </div>
                    <span className={`w-fit rounded-full border px-3 py-1 text-xs font-semibold ${requestStatusClass(request.status)}`}>{formatHorseRetirementRequestStatus(request.status)}</span>
                  </div>
                  <div className="mt-5 grid gap-4 lg:grid-cols-2">
                    <section className="rounded-lg border border-stone-800 bg-stone-950/60 p-4"><p className="text-xs font-semibold tracking-[0.14em] text-stone-500">申请事实</p><p className="mt-2 font-medium text-stone-100">{formatHorseRetirementRequestKind(request.request_kind)}</p><p className="mt-2 text-sm text-stone-400">提交于 {formatDateTime(request.requested_at)}</p>{request.player_note && <p className="mt-3 text-sm leading-6 text-stone-300">玩家备注：{request.player_note}</p>}{request.gm_reason && <p className="mt-3 text-sm leading-6 text-stone-300">GM 原因：{request.gm_reason}</p>}</section>
                    <section className={`${futureEntries.length ? "border-red-400/35 bg-red-400/5" : "border-emerald-400/35 bg-emerald-400/5"} rounded-lg border p-4`}><p className="text-xs font-semibold tracking-[0.14em] text-stone-500">未来已确认赛程</p>{futureEntries.length ? <div className="mt-2 space-y-2">{futureEntries.map((entry) => <p className="text-sm text-red-100" key={entry.id}>{formatWpTime(entry.wp_year, entry.wp_month, entry.wp_week)} · {entry.race_label || entry.race_kind}</p>)}<p className="pt-1 text-xs leading-5 text-red-200">存在未来已确认赛程，当前不能确认退役。请先按既有赛程流程处理；本页面不会自动变更或删除它们。</p></div> : <p className="mt-2 text-sm text-emerald-100">没有未来已确认赛程，可以进入确认前复核。</p>}</section>
                  </div>
                  <section className="mt-4 rounded-lg border border-stone-800 bg-stone-950/60 p-4"><div className="flex flex-col gap-2 sm:flex-row sm:items-start sm:justify-between"><div><p className="text-xs font-semibold tracking-[0.14em] text-stone-500">待释放奖金预览</p><p className="mt-2 text-sm text-stone-400">按奖金应收记录中的马主分组，而非当前马主。0 笔也可以确认退役。</p></div><p className="break-all font-mono text-lg font-semibold text-amber-100">{formatGameMoney(sumMoney(pendingPrizes))}</p></div><div className="mt-4 grid gap-3 sm:grid-cols-2">{Array.from(prizeByOwner.entries()).map(([ownerId, rows]) => <div className="rounded border border-stone-800 p-3" key={ownerId}><p className="text-xs text-stone-500">历史马主</p><p className="mt-1 text-sm text-stone-100">{ownerNameById.get(ownerId) ?? "未知马主"}</p><p className="mt-2 font-mono text-amber-100">{formatGameMoney(sumMoney(rows))} · {rows.length} 笔</p></div>)}{!pendingPrizes.length && <p className="text-sm text-stone-500">无待释放奖金；确认流程仍会完成马匹退役并保留完整审计。</p>}</div></section>
                  <div className="mt-5 grid gap-4 border-t border-stone-800 pt-5 lg:grid-cols-2"><ActionForm action={reject} className="rounded-lg border border-red-400/25 bg-red-400/5 p-4" confirmation="确认拒绝这条退役申请吗？马匹会恢复为现役状态，且该拒绝原因将保留在记录中。" pendingLabel="正在拒绝…" submitLabel="拒绝申请" variant="danger"><label className="admin-label">拒绝原因<textarea className="admin-input min-h-20" name="reason" required /></label></ActionForm>{futureEntries.length ? <div className="rounded-lg border border-stone-700 bg-stone-950/60 p-4"><p className="font-medium text-stone-300">暂不能确认退役</p><p className="mt-2 text-sm leading-6 text-stone-500">先处理上述未来已确认赛程。数据库也会在确认时再次验证，以防并发变化。</p></div> : <ActionForm action={confirm} className="rounded-lg border border-amber-300/35 bg-amber-300/5 p-4" confirmation="最终确认：此操作会永久将马匹设为已退役，并在同一数据库事务中释放该马匹 所有待释放奖金。确认后不能通过普通流程撤销。" pendingLabel="正在确认并结算…" submitLabel="确认退役并结算奖金" variant="danger"><p className="text-sm leading-6 text-amber-100">确认成功后请以刷新后的实际结果为准；数据库采用幂等保护，不会重复释放奖金。</p></ActionForm>}</div>
                </article>
              );
            })}
            {!pendingRequests.length && <p className="rounded-xl border border-stone-800 bg-stone-900 p-6 text-sm text-stone-500">当前没有等待处理的退役申请。</p>}
          </div>
        </section>
      </section>

      <section className="scroll-mt-32 mt-10 border-t border-stone-800 pt-10" id="history">
        <h2 className="text-xl font-semibold text-amber-200">近期完成与历史申请</h2>
        <p className="mt-2 text-sm text-stone-400">包含确认、拒绝与撤回记录。马匹与马主关系为申请时的历史快照；这里仅限 GM。</p>
        <div className="mt-5 grid gap-4 lg:grid-cols-2">{historyRequests.slice(0, 30).map((request) => { const horse = horseById.get(request.horse_id); return <article className="rounded-xl border border-stone-800 bg-stone-900 p-5" key={request.id}><div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between"><div><p className="font-semibold text-stone-100">{formatHorseName(horse)}</p><p className="mt-1 text-sm text-stone-400">{formatHorseRetirementRequestKind(request.request_kind)} · 马主：{ownerNameById.get(request.owner_id) ?? "—"}</p></div><span className={`w-fit rounded-full border px-3 py-1 text-xs font-semibold ${requestStatusClass(request.status)}`}>{formatHorseRetirementRequestStatus(request.status)}</span></div><p className="mt-4 text-sm text-stone-400">提交：{formatDateTime(request.requested_at)} · 完成/处理：{formatDateTime(request.completed_at ?? request.withdrawn_at ?? request.reviewed_at)}</p>{request.player_note && <p className="mt-3 rounded-lg border border-stone-800 bg-stone-950/60 p-3 text-sm leading-6 text-stone-400">玩家备注：{request.player_note}</p>}{request.gm_reason && <p className="mt-3 rounded-lg border border-stone-800 bg-stone-950/60 p-3 text-sm leading-6 text-stone-400">GM 原因：{request.gm_reason}</p>}</article>; })}{!historyRequests.length && <p className="rounded-xl border border-stone-800 bg-stone-900 p-6 text-sm text-stone-500">暂无已完成的退役申请。</p>}</div>
      </section>

      <section className="scroll-mt-32 mt-10 border-t border-stone-800 pt-10" id="prizes">
        <h2 className="text-xl font-semibold text-amber-200">奖金账本历史</h2>
        <p className="mt-2 text-sm leading-6 text-stone-400">仅 GM 可见的 append-only 账本投影。奖金释放、已释放奖金纠错与赛果作废冲回均以正式资金流水为依据；这里不提供手工改账能力。</p>
        <div className="mt-5 space-y-3">{((ledgerEntries ?? []) as LedgerEntry[]).slice(0, 50).map((entry) => { const receivable = receivableById.get(entry.prize_receivable_id); const horse = receivable ? horseById.get(receivable.horse_id) : undefined; const request = requestById.get(entry.retirement_request_id); return <article className="rounded-xl border border-stone-800 bg-stone-900 p-5" key={entry.id}><div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between"><div><p className="font-semibold text-stone-100">{formatPrizeReceivableLedgerEntryKind(entry.entry_kind)}</p><p className="mt-1 text-sm text-stone-400">{formatHorseName(horse)} · 历史马主：{receivable ? ownerNameById.get(receivable.owner_id) ?? "—" : "—"}</p></div><p className={`break-all font-mono text-lg font-semibold ${BigInt(entry.amount_delta) < 0 ? "text-red-200" : "text-emerald-100"}`}>{formatGameMoney(entry.amount_delta)}</p></div><p className="mt-3 text-sm text-stone-400">关联申请：{request ? formatHorseRetirementRequestKind(request.request_kind) : "—"} · {formatDateTime(entry.created_at)}</p>{entry.reason && <p className="mt-3 rounded-lg border border-stone-800 bg-stone-950/60 p-3 text-sm text-stone-400">原因：{entry.reason}</p>}</article>; })}{!(ledgerEntries ?? []).length && <p className="rounded-xl border border-stone-800 bg-stone-900 p-6 text-sm text-stone-500">尚无奖金账本记录。</p>}</div>
      </section>
    </main>
  );
}
