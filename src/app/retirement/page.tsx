import Link from "next/link";

import { withdrawHorseRetirementRequest } from "@/app/retirement/actions";
import { ActionForm } from "@/components/action-form";
import { AppShell } from "@/components/app-shell";
import { Notice } from "@/components/notice";
import { requirePlayer } from "@/lib/auth/session";
import {
  formatDateTime,
  formatGameMoney,
  formatHorseLifeStage,
  formatHorseName,
  formatHorseRetirementRequestKind,
  formatHorseRetirementRequestStatus,
  formatWpTime,
} from "@/lib/format";

type PageProps = { searchParams: Promise<{ notice?: string }> };

type PrizeReceivable = {
  prize_receivable_id: string;
  race_result_id: string;
  horse_id: string;
  amount: string | number | bigint;
  created_at: string;
  updated_at: string;
};

type PublicResult = {
  race_result_id: string;
  horse_id: string;
  wp_year: number;
  wp_month: number;
  wp_week: number;
  race_name: string;
  grade: string | null;
  finish_position: number;
};

function sumMoney(rows: PrizeReceivable[]) {
  return rows.reduce((total, row) => total + BigInt(row.amount), BigInt(0));
}

function requestStatusClass(status: string) {
  if (status === "PENDING") return "border-amber-300/40 bg-amber-300/10 text-amber-100";
  if (status === "CONFIRMED") return "border-emerald-400/40 bg-emerald-400/10 text-emerald-100";
  if (status === "REJECTED") return "border-red-400/40 bg-red-400/10 text-red-100";
  return "border-stone-700 bg-stone-800 text-stone-300";
}

export const dynamic = "force-dynamic";

export default async function RetirementPage({ searchParams }: PageProps) {
  const [{ supabase, user }, { notice }] = await Promise.all([requirePlayer(), searchParams]);
  const [{ data: requests, error: requestError }, { data: horses, error: horseError }, { data: rawPrizes, error: prizeError }, { data: gameState, error: gameStateError }] = await Promise.all([
    supabase
      .from("horse_retirement_requests")
      .select("id, horse_id, request_kind, status, player_note, gm_reason, requested_at, reviewed_at, withdrawn_at, completed_at")
      .order("requested_at", { ascending: false }),
    supabase.from("horses").select("id, horse_number, foal_name, translated_name, life_stage").order("horse_number"),
    supabase.rpc("get_current_owner_prize_receivables"),
    supabase.from("game_state").select("current_wp_year, current_wp_month, current_wp_week").maybeSingle(),
  ]);

  const prizes = (Array.isArray(rawPrizes) ? rawPrizes : []) as PrizeReceivable[];
  const resultIds = prizes.map((prize) => prize.race_result_id);
  const { data: results, error: resultError } = resultIds.length
    ? await supabase
      .from("race_results_public")
      .select("race_result_id, horse_id, wp_year, wp_month, wp_week, race_name, grade, finish_position")
      .in("race_result_id", resultIds)
    : { data: [], error: null };

  const dataError = requestError || horseError || prizeError || gameStateError || resultError;
  const horseById = new Map((horses ?? []).map((horse) => [horse.id, horse]));
  const resultById = new Map((results ?? []).map((result) => [result.race_result_id, result as PublicResult]));
  const prizesByHorseId = new Map<string, PrizeReceivable[]>();
  for (const prize of prizes) {
    prizesByHorseId.set(prize.horse_id, [...(prizesByHorseId.get(prize.horse_id) ?? []), prize]);
  }
  const totalPendingPrize = sumMoney(prizes);

  return (
    <AppShell email={user.email} isGM={false}>
      <main className="mx-auto w-full max-w-6xl px-4 py-8 sm:px-6 sm:py-10">
        <section className="flex flex-col gap-5 border-b border-stone-800 pb-7 lg:flex-row lg:items-end lg:justify-between">
          <div>
            <p className="text-sm font-semibold tracking-[0.24em] text-amber-300">玩家 · 退役管理</p>
            <h1 className="mt-3 text-3xl font-semibold tracking-tight">退役与待释放奖金</h1>
            <p className="mt-3 max-w-3xl text-sm leading-6 text-stone-400">退役申请先进入 GM 审核。只有 GM 确认退役后，属于该马匹历史马主 的待释放奖金才会成为正式资金；它不等同于当前账户余额或可用资金。</p>
          </div>
          <div className="rounded-xl border border-amber-300/30 bg-amber-300/5 px-5 py-4 text-sm">
            <p className="text-stone-500">我的待释放奖金</p>
            <p className="mt-1 break-all font-mono text-2xl font-semibold text-amber-100">{formatGameMoney(totalPendingPrize)}</p>
            <p className="mt-2 text-xs leading-5 text-stone-500">不计入账户资金或可用资金。</p>
          </div>
        </section>

        <Notice message={notice} />
        {dataError && <p className="mt-5 rounded-xl border border-red-400/40 bg-red-400/5 p-4 text-sm leading-6 text-red-100">部分退役或奖金资料暂时无法读取。请刷新页面；不会显示数据库内部错误。</p>}

        <section className="mt-8">
          <div className="flex items-end justify-between gap-4">
            <div>
              <h2 className="text-xl font-semibold text-amber-200">待释放奖金明细</h2>
              <p className="mt-2 text-sm text-stone-400">只显示当前玩家马主 自己的 待释放奖金应收。已释放、纠错与作废历史不会在此处显示。</p>
            </div>
            <span className="font-mono text-sm text-stone-500">{prizes.length} 笔</span>
          </div>
          <div className="mt-5 grid gap-4 lg:grid-cols-2">
            {prizes.map((prize) => {
              const horse = horseById.get(prize.horse_id);
              const result = resultById.get(prize.race_result_id);
              return (
                <article className="rounded-xl border border-stone-800 bg-stone-900 p-5" key={prize.prize_receivable_id}>
                  <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
                    <div>
                      <Link className="font-semibold text-stone-100 hover:text-amber-100" href={`/horses/${prize.horse_id}`}>{formatHorseName(horse)}</Link>
                      <p className="mt-1 font-mono text-xs text-stone-500">#{horse?.horse_number ?? "—"}</p>
                    </div>
                    <p className="break-all font-mono text-lg font-semibold text-amber-100">{formatGameMoney(prize.amount)}</p>
                  </div>
                  {result ? <p className="mt-4 text-sm leading-6 text-stone-400">赛果：{result.race_name}{result.grade ? ` · ${result.grade}` : ""} · {result.finish_position} 着 · {formatWpTime(result.wp_year, result.wp_month, result.wp_week)}</p> : <p className="mt-4 text-sm text-stone-500">关联公开赛果暂时不可用。</p>}
                  <p className="mt-3 text-xs text-stone-500">应收创建于 {formatDateTime(prize.created_at)}</p>
                </article>
              );
            })}
            {!prizes.length && <p className="rounded-xl border border-stone-800 bg-stone-900 p-6 text-sm leading-6 text-stone-500">当前没有待释放奖金。比赛获得赏金与已释放资金会在各自的受控流程中处理。</p>}
          </div>
        </section>

        <section className="mt-10 border-t border-stone-800 pt-10">
          <div className="flex flex-col gap-3 sm:flex-row sm:items-end sm:justify-between">
            <div>
              <h2 className="text-xl font-semibold text-amber-200">我的退役申请历史</h2>
              <p className="mt-2 text-sm text-stone-400">你只能看到自己马主 的记录。待处理的马主主动申请可在 GM 审核前撤回。</p>
            </div>
            <p className="text-sm text-stone-500">当前 WP：{gameState ? formatWpTime(gameState.current_wp_year, gameState.current_wp_month, gameState.current_wp_week) : "尚未初始化"}</p>
          </div>
          <div className="mt-5 space-y-4">
            {(requests ?? []).map((request) => {
              const horse = horseById.get(request.horse_id);
              const withdraw = withdrawHorseRetirementRequest.bind(null, request.horse_id, request.id, "/retirement");
              const prizeForHorse = prizesByHorseId.get(request.horse_id) ?? [];
              return (
                <article className="rounded-xl border border-stone-800 bg-stone-900 p-5" key={request.id}>
                  <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
                    <div>
                      <Link className="font-semibold text-stone-100 hover:text-amber-100" href={`/horses/${request.horse_id}`}>{formatHorseName(horse)}</Link>
                      <p className="mt-1 text-sm text-stone-400">{formatHorseRetirementRequestKind(request.request_kind)} · 提交于 {formatDateTime(request.requested_at)}</p>
                    </div>
                    <span className={`w-fit rounded-full border px-3 py-1 text-xs font-semibold ${requestStatusClass(request.status)}`}>{formatHorseRetirementRequestStatus(request.status)}</span>
                  </div>
                  <div className="mt-5 grid gap-3 text-sm sm:grid-cols-2 lg:grid-cols-3">
                    <div><p className="text-xs text-stone-500">当前马匹状态</p><p className="mt-1 text-stone-200">{formatHorseLifeStage(horse?.life_stage)}</p></div>
                    <div><p className="text-xs text-stone-500">此马当前待释放奖金</p><p className="mt-1 font-mono text-amber-100">{formatGameMoney(sumMoney(prizeForHorse))}</p></div>
                    <div><p className="text-xs text-stone-500">最后处理时间</p><p className="mt-1 text-stone-200">{formatDateTime(request.completed_at ?? request.withdrawn_at ?? request.reviewed_at)}</p></div>
                  </div>
                  {request.player_note && <p className="mt-4 rounded-lg border border-stone-800 bg-stone-950/60 p-3 text-sm leading-6 text-stone-400">你的备注：{request.player_note}</p>}
                  {request.status === "REJECTED" && request.gm_reason && <p className="mt-4 rounded-lg border border-red-400/30 bg-red-400/5 p-3 text-sm leading-6 text-red-100">GM 拒绝原因：{request.gm_reason}</p>}
                  {request.status === "PENDING" && request.request_kind === "OWNER_REQUEST" && <ActionForm action={withdraw} className="mt-4" confirmation="确定撤回这条退役申请吗？Horse 将恢复为现役，GM 审核流程会停止。" pendingLabel="正在撤回…" submitLabel="撤回退役申请" variant="secondary" />}
                </article>
              );
            })}
            {!(requests ?? []).length && <p className="rounded-xl border border-stone-800 bg-stone-900 p-6 text-sm text-stone-500">尚未提交退役申请。可在自己马匹的详情页查看是否符合 马主主动申请条件。</p>}
          </div>
        </section>
      </main>
    </AppShell>
  );
}
