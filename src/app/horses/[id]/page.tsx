import Link from "next/link";
import { notFound } from "next/navigation";

import { submitHorseRetirementRequest, withdrawHorseRetirementRequest } from "@/app/retirement/actions";
import { ActionForm } from "@/components/action-form";
import { AppShell } from "@/components/app-shell";
import { HorseHealthPanel, type HealthInjury, type HorseHealthEvent } from "@/components/horse-health-panel";
import { Notice } from "@/components/notice";
import { StatusBadge } from "@/components/ui/primitives";
import { requireUser } from "@/lib/auth/session";
import { formatDateTime, formatGameMoney, formatHorseLifeStage, formatHorseSex, formatPedigreeFactorKind, formatRaceGrade, formatWpTime } from "@/lib/format";

type PageProps = { params: Promise<{ id: string }>; searchParams: Promise<{ notice?: string }> };

type PrizeReceivable = {
  horse_id: string;
  amount: string | number | bigint;
};

function sumMoney(rows: PrizeReceivable[]) {
  return rows.reduce((total, row) => total + BigInt(row.amount), BigInt(0));
}

export default async function HorsePage({ params, searchParams }: PageProps) {
  const [{ id }, { notice }, { supabase, user, profile }] = await Promise.all([params, searchParams, requireUser()]);
  const [{ data: horse }, { data: factors }, { data: publicResults }, { data: injuries }, { data: healthEvents }] = await Promise.all([
    supabase.from("horses").select("*").eq("id", id).maybeSingle(),
    supabase.from("horse_factors").select("factor_kind, factor_name").eq("horse_id", id).order("created_at"),
    supabase.from("race_results_public").select("race_result_id, actual_race_id, wp_year, wp_month, wp_week, race_name, grade, finish_position, prize_amount, actual_jockey, actual_running_style, recorded_at").eq("horse_id", id).order("wp_year", { ascending: false }).order("wp_month", { ascending: false }).order("wp_week", { ascending: false }).order("recorded_at", { ascending: false }),
    supabase.from("injuries_public").select("id, status, wp_start_year, wp_start_month, wp_start_week, wp_end_year, wp_end_month, wp_end_week, notes").eq("horse_id", id).order("wp_start_year", { ascending: false }).order("wp_start_month", { ascending: false }).order("wp_start_week", { ascending: false }),
    supabase.from("horse_health_events_public").select("id, event_type, status, wp_year, wp_month, wp_week, stamina_before, stamina_after").eq("horse_id", id).order("wp_year", { ascending: false }).order("wp_month", { ascending: false }).order("wp_week", { ascending: false }),
  ]);

  if (!horse) { notFound(); }
  const { data: owner } = horse.owner_id
    ? await supabase.from("owners").select("id, display_name").eq("id", horse.owner_id).maybeSingle()
    : { data: null };

  const isOwnPlayerHorse = profile?.role === "PLAYER" && profile.owner_id === horse.owner_id;
  const [{ data: gameState }, { data: retirementRequests }, { data: rawPrizes, error: prizeError }] = await Promise.all([
    supabase.from("game_state").select("current_wp_year, current_wp_month, current_wp_week").maybeSingle(),
    isOwnPlayerHorse
      ? supabase
        .from("horse_retirement_requests")
        .select("id, request_kind, status, player_note, gm_reason, requested_at")
        .eq("horse_id", horse.id)
        .order("requested_at", { ascending: false })
      : Promise.resolve({ data: [] }),
    isOwnPlayerHorse
      ? supabase.rpc("get_current_owner_prize_receivables")
      : Promise.resolve({ data: [], error: null }),
  ]);
  const retirementRequest = retirementRequests?.[0] ?? null;
  const ownPrizes = ((Array.isArray(rawPrizes) ? rawPrizes : []) as PrizeReceivable[]).filter((prize) => prize.horse_id === horse.id);
  const pendingPrize = sumMoney(ownPrizes);
  const wpAge = gameState ? gameState.current_wp_year - horse.birth_year : null;
  const canSubmitRetirement = isOwnPlayerHorse && horse.life_stage === "ACTIVE" && wpAge !== null && wpAge >= 3;
  const submitRetirement = submitHorseRetirementRequest.bind(null, horse.id);
  const withdrawRetirement = retirementRequest
    ? withdrawHorseRetirementRequest.bind(null, horse.id, retirementRequest.id, `/horses/${horse.id}`)
    : null;

  const fields = [
    ["马号", horse.horse_number],
    ["出生年", horse.birth_year],
    ["性别", formatHorseSex(horse.sex)],
    ["毛色", horse.coat_color],
    ["父", horse.sire_horse_id ? <Link className="text-amber-200 hover:text-amber-100" href={`/horses/${horse.sire_horse_id}`}>{horse.sire_name}</Link> : horse.sire_name],
    ["父系", horse.sire_line],
    ["母", horse.dam_horse_id ? <Link className="text-amber-200 hover:text-amber-100" href={`/horses/${horse.dam_horse_id}`}>{horse.dam_name || "—"}</Link> : horse.dam_name ?? "—"],
    ["母父", horse.broodmare_sire_name],
    ["骑手", horse.current_jockey_name ?? "—"],
    ["调教师", horse.current_trainer_name ?? "—"],
    ["生命周期", formatHorseLifeStage(horse.life_stage)],
    ["马主", owner?.display_name ?? "未归属"],
  ];
  const results = publicResults ?? [];
  const publicInjuries: HealthInjury[] = (injuries ?? []).map((injury) => ({
    id: injury.id,
    status: injury.status,
    startYear: injury.wp_start_year,
    startMonth: injury.wp_start_month,
    startWeek: injury.wp_start_week,
    endYear: injury.wp_end_year,
    endMonth: injury.wp_end_month,
    endWeek: injury.wp_end_week,
    notes: injury.notes,
  }));
  const publicHealthEvents: HorseHealthEvent[] = (healthEvents ?? []).map((event) => ({
    id: event.id,
    eventType: event.event_type,
    status: event.status,
    wpYear: event.wp_year,
    wpMonth: event.wp_month,
    wpWeek: event.wp_week,
    staminaBefore: event.stamina_before,
    staminaAfter: event.stamina_after,
  }));
  const wins = results.filter((result) => result.finish_position === 1);
  const g1Wins = wins.filter((result) => result.grade === "G1");
  const totalPrize = results.reduce((sum, result) => sum + BigInt(result.prize_amount), BigInt(0));

  return (
    <AppShell email={user.email} isGM={profile?.role === "GM"}>
      <main className="page-wrap">
        <Link className="inline-flex min-h-11 items-center text-sm font-semibold text-[#7d5b24] hover:text-[#173f35]" href="/horses">← 返回马匹档案</Link>
        <Notice message={notice} />
        <div className="mt-3 grid gap-6 xl:grid-cols-[minmax(0,1fr)_18rem]">
        <section className="rounded-2xl border border-stone-800 bg-stone-900 p-5 shadow-[0_14px_36px_rgb(57_47_31/7%)] sm:p-7">
          <p className="text-sm font-semibold tracking-[0.18em] text-amber-300">马匹 #{horse.horse_number}</p>
          <h1 className="display-title mt-3 text-3xl font-semibold text-[#173f35] sm:text-4xl">{horse.translated_name || horse.foal_name}</h1>
          {horse.name_katakana && <p className="mt-2 text-stone-400">{horse.name_katakana}</p>}
          <dl className="mt-8 grid gap-5 sm:grid-cols-2">
            {fields.map(([label, value]) => <div key={label}><dt className="text-xs font-medium tracking-wide text-stone-500">{label}</dt><dd className="mt-1 text-stone-100">{value}</dd></div>)}
          </dl>
          <div className="mt-8 border-t border-stone-800 pt-6">
            <h2 className="font-semibold text-amber-200">血统因子</h2>
            <div className="mt-3 flex flex-wrap gap-2">
              {(factors ?? []).map((factor) => <span className="rounded-full border border-stone-700 px-3 py-1 text-sm text-stone-300" key={`${factor.factor_kind}-${factor.factor_name}`}><span className="mr-1 text-xs text-amber-300">{formatPedigreeFactorKind(factor.factor_kind)}</span>{factor.factor_name}</span>)}
              {!factors?.length && <p className="text-sm text-stone-500">尚未记录血统因子。</p>}
            </div>
          </div>
          <div className="mt-8 border-t border-stone-800 pt-6">
            <h2 className="font-semibold text-amber-200">战绩</h2>
            <p className="mt-2 text-sm leading-6 text-stone-400">仅按当前有效公开赛果派生。比赛获得赏金总额不代表马主当前已结算资金；已作废赛果不计入。</p>
            <dl className="mt-5 grid gap-3 sm:grid-cols-2 lg:grid-cols-4"><div className="rounded-lg border border-stone-800 bg-stone-950/60 p-4"><dt className="text-xs text-stone-500">出赛数</dt><dd className="mt-2 text-2xl font-semibold text-stone-100">{results.length}</dd></div><div className="rounded-lg border border-stone-800 bg-stone-950/60 p-4"><dt className="text-xs text-stone-500">胜场</dt><dd className="mt-2 text-2xl font-semibold text-stone-100">{wins.length}</dd></div><div className="rounded-lg border border-stone-800 bg-stone-950/60 p-4"><dt className="text-xs text-stone-500">G1 胜场</dt><dd className="mt-2 text-2xl font-semibold text-stone-100">{g1Wins.length}</dd></div><div className="rounded-lg border border-stone-800 bg-stone-950/60 p-4"><dt className="text-xs text-stone-500">比赛获得赏金总额</dt><dd className="mt-2 break-all text-lg font-semibold text-amber-100">{formatGameMoney(totalPrize)}</dd></div></dl>
            {g1Wins.length > 0 && <div className="mt-6"><h3 className="text-sm font-semibold text-amber-100">G1 胜鞍</h3><div className="mt-3 grid gap-3 sm:grid-cols-2">{g1Wins.map((result) => <article className="rounded-lg border border-amber-300/25 bg-amber-300/5 p-4" key={result.race_result_id}><p className="font-medium text-stone-100">{result.race_name}</p><p className="mt-1 text-sm text-stone-400">{formatWpTime(result.wp_year, result.wp_month, result.wp_week)} · {formatRaceGrade(result.grade)}</p></article>)}</div></div>}
            <div className="mt-6 space-y-3">{results.map((result) => <article className="rounded-lg border border-stone-800 bg-stone-950/50 p-4" key={result.race_result_id}><div className="flex flex-col gap-2 sm:flex-row sm:items-start sm:justify-between"><div><p className="font-medium text-stone-100">{result.race_name} {result.grade && <span className="ml-2 text-xs text-amber-100">{formatRaceGrade(result.grade)}</span>}</p><p className="mt-1 text-sm text-stone-400">{formatWpTime(result.wp_year, result.wp_month, result.wp_week)} · 骑手：{result.actual_jockey || "未指定"} · 跑法：{result.actual_running_style || "未指定"}</p></div><p className="font-semibold text-amber-100">{result.finish_position} 着 · {formatGameMoney(result.prize_amount)}</p></div></article>)}{!results.length && <p className="rounded-lg border border-stone-800 bg-stone-950/60 p-5 text-sm text-stone-500">暂无正式比赛记录。</p>}</div>
          </div>
          <HorseHealthPanel currentStamina={horse.current_stamina} events={publicHealthEvents} horseId={horse.id} injuries={publicInjuries} isGM={false} />
          {isOwnPlayerHorse && (
            <div className="mt-8 border-t border-stone-800 pt-6">
              <div className="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
                <div>
                  <h2 className="font-semibold text-amber-200">退役申请</h2>
                  <p className="mt-2 text-sm leading-6 text-stone-400">当前状态：<span className="font-medium text-stone-200">{formatHorseLifeStage(horse.life_stage)}</span>。主动申请只会让马匹进入退役处理中；GM 确认前不会退役、不会释放待释放奖金，也不会开启繁殖。</p>
                </div>
                <Link className="w-fit text-sm text-amber-200 hover:text-amber-100" href="/retirement">查看我的退役与奖金 →</Link>
              </div>
              <div className="mt-5 grid gap-4 sm:grid-cols-2">
                <div className="rounded-lg border border-stone-800 bg-stone-950/60 p-4"><p className="text-xs text-stone-500">当前 WP 年龄</p><p className="mt-2 text-xl font-semibold text-stone-100">{wpAge === null ? "尚未初始化" : `${wpAge} 岁`}</p></div>
                <div className="rounded-lg border border-stone-800 bg-stone-950/60 p-4"><p className="text-xs text-stone-500">此马的待释放奖金</p><p className="mt-2 break-all font-mono text-xl font-semibold text-amber-100">{formatGameMoney(pendingPrize)}</p><p className="mt-2 text-xs leading-5 text-stone-500">不计入账户资金或可用资金。</p></div>
              </div>
              {prizeError && <p className="mt-4 rounded-lg border border-red-400/30 bg-red-400/5 p-3 text-sm text-red-100">待释放奖金暂时无法读取，请刷新后重试。</p>}
              {horse.life_stage === "RETIRE_PENDING" ? <div className="mt-5 rounded-lg border border-amber-300/35 bg-amber-300/5 p-4"><p className="font-medium text-amber-100">已有退役申请处理中</p>{retirementRequest ? <><p className="mt-2 text-sm text-stone-400">提交于 {formatDateTime(retirementRequest.requested_at)}。GM 审核期间不能新建已确认赛程。</p>{retirementRequest.request_kind === "OWNER_REQUEST" && withdrawRetirement && <ActionForm action={withdrawRetirement} className="mt-4" confirmation="确定撤回这条退役申请吗？马匹将恢复为现役，GM 审核流程会停止。" pendingLabel="正在撤回…" submitLabel="撤回退役申请" variant="secondary" />}</> : <p className="mt-2 text-sm text-amber-100">申请记录暂时无法读取，请刷新后重试。</p>}</div> : horse.life_stage === "RETIRED" ? pendingPrize > BigInt(0) ? <p className="mt-5 rounded-lg border border-red-400/35 bg-red-400/5 p-4 text-sm leading-6 text-red-100">数据异常：该马匹已退役但仍显示待释放奖金。页面不会自行修正，请联系 GM 处理。</p> : <p className="mt-5 rounded-lg border border-emerald-400/30 bg-emerald-400/5 p-4 text-sm text-emerald-100">该马匹已退役，当前没有待释放奖金。</p> : !gameState ? <p className="mt-5 rounded-lg border border-amber-300/30 bg-amber-300/5 p-4 text-sm text-amber-100">GM 尚未设置游戏时间，暂时不能提交退役申请。</p> : horse.life_stage !== "ACTIVE" ? <p className="mt-5 rounded-lg border border-stone-700 bg-stone-950/60 p-4 text-sm text-stone-400">该马匹当前不是现役状态，不能主动申请退役。</p> : wpAge !== null && wpAge < 3 ? <p className="mt-5 rounded-lg border border-stone-700 bg-stone-950/60 p-4 text-sm text-stone-400">3岁起可主动申请退役。</p> : canSubmitRetirement ? <ActionForm action={submitRetirement} className="mt-5 rounded-lg border border-amber-300/30 bg-amber-300/5 p-4" confirmation="确认提交退役申请吗？提交后马匹会进入退役处理中，并阻止新的已确认赛程；这不会立即退役或释放奖金。" pendingLabel="正在提交…" submitLabel="提交退役申请"><input name="return_path" type="hidden" value={`/horses/${horse.id}`} /><label className="admin-label">玩家备注（可选）<textarea className="admin-input min-h-24" name="player_note" placeholder="例如：希望本季结束后退役" /></label></ActionForm> : null}
            </div>
          )}
        </section>
        <aside className="space-y-4 xl:sticky xl:top-24 xl:self-start">
          <section className="club-card">
            <p className="page-eyebrow">当前状态</p>
            <div className="mt-3"><StatusBadge tone={horse.life_stage === "ACTIVE" ? "success" : "neutral"}>{formatHorseLifeStage(horse.life_stage)}</StatusBadge></div>
            <dl className="mt-5 space-y-4 text-sm">
              <div><dt className="text-xs font-bold tracking-[0.12em] text-[#808881]">马主</dt><dd className="mt-1 font-semibold text-[#173f35]">{owner?.display_name ?? "未归属"}</dd></div>
              <div className="border-t border-[#d8d0c2] pt-4"><dt className="text-xs font-bold uppercase tracking-[0.12em] text-[#808881]">当前 WP 年龄</dt><dd className="mt-1 font-semibold text-[#202521]">{wpAge === null ? "尚未初始化" : `${wpAge} 岁`}</dd></div>
              <div className="border-t border-[#d8d0c2] pt-4"><dt className="text-xs font-bold uppercase tracking-[0.12em] text-[#808881]">当前体力</dt><dd className="mt-1 font-mono text-xl font-semibold text-[#202521]">{horse.current_stamina}</dd></div>
            </dl>
          </section>
          <section className="rounded-2xl border border-[#cfc2a8] bg-[#173f35] p-5 text-white shadow-[0_14px_34px_rgb(23_63_53/18%)]">
            <p className="text-xs font-bold tracking-[0.18em] text-[#d6b66a]">生涯</p>
            <dl className="mt-4 grid grid-cols-2 gap-4">
              <div><dt className="text-xs text-[#b9c6bf]">出赛</dt><dd className="mt-1 text-2xl font-semibold">{results.length}</dd></div>
              <div><dt className="text-xs text-[#b9c6bf]">胜场</dt><dd className="mt-1 text-2xl font-semibold">{wins.length}</dd></div>
              <div><dt className="text-xs text-[#b9c6bf]">G1</dt><dd className="mt-1 text-2xl font-semibold text-[#ead79c]">{g1Wins.length}</dd></div>
              <div><dt className="text-xs text-[#b9c6bf]">总赏金</dt><dd className="mt-1 break-all font-mono text-sm font-semibold text-[#ead79c]">{formatGameMoney(totalPrize)}</dd></div>
            </dl>
          </section>
        </aside>
        </div>
      </main>
    </AppShell>
  );
}
