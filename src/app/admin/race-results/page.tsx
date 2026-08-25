import Link from "next/link";

import { createActualRace } from "@/app/admin/race-results/actions";
import { ActualRaceForm, type ActualRaceCatalogOption } from "@/components/actual-race-form";
import { Notice } from "@/components/notice";
import { requireGM } from "@/lib/auth/session";
import { formatDateTime, formatHorseName, formatRaceGrade, formatRaceKind, formatWpTime } from "@/lib/format";

type PageProps = { searchParams: Promise<{ notice?: string }> };

export const dynamic = "force-dynamic";

export default async function AdminRaceResultsPage({ searchParams }: PageProps) {
  const [{ supabase }, { notice }] = await Promise.all([requireGM(), searchParams]);
  const [{ data: gameState, error: gameStateError }, { data: actualRaces, error: actualRaceError }, { data: results, error: resultError }, { data: entries, error: entryError }, { data: horses, error: horseError }, { data: owners, error: ownerError }, { data: catalogs, error: catalogError }] = await Promise.all([
    supabase.from("game_state").select("current_wp_year, current_wp_month, current_wp_week").maybeSingle(),
    supabase.from("actual_races").select("id, wp_year, wp_month, wp_week, race_kind, race_catalog_id, race_name, grade, created_at").order("wp_year", { ascending: false }).order("wp_month", { ascending: false }).order("wp_week", { ascending: false }).order("created_at", { ascending: false }),
    supabase.from("race_results").select("id, confirmed_race_entry_id, actual_race_id, horse_id, status, finish_position, prize_amount, recorded_at").order("recorded_at", { ascending: false }),
    supabase.from("confirmed_race_entries").select("id, horse_id, owner_id, wp_year, wp_month, wp_week, race_kind, race_catalog_id, race_label, jockey, running_style, request_id, confirmed_at").order("confirmed_at", { ascending: false }),
    supabase.from("horses").select("id, horse_number, foal_name, translated_name").order("horse_number"),
    supabase.from("owners").select("id, display_name").order("display_name"),
    supabase.from("race_catalog").select("id, name, grade, default_wp_month, default_wp_week, is_active").order("name"),
  ]);

  const dataError = gameStateError || actualRaceError || resultError || entryError || horseError || ownerError || catalogError;
  const horseById = new Map((horses ?? []).map((horse) => [horse.id, horse]));
  const ownerNameById = new Map((owners ?? []).map((owner) => [owner.id, owner.display_name]));
  const catalogNameById = new Map((catalogs ?? []).map((catalog) => [catalog.id, catalog.name]));
  const activeResultEntryIds = new Set((results ?? []).filter((result) => result.status === "CONFIRMED").map((result) => result.confirmed_race_entry_id));
  const resultCountByActualRace = new Map<string, number>();
  for (const result of results ?? []) if (result.status === "CONFIRMED") resultCountByActualRace.set(result.actual_race_id, (resultCountByActualRace.get(result.actual_race_id) ?? 0) + 1);
  const pendingEntries = (entries ?? []).filter((entry) => !activeResultEntryIds.has(entry.id));
  const overdueEntries = gameState ? pendingEntries.filter((entry) => (entry.wp_year < gameState.current_wp_year || (entry.wp_year === gameState.current_wp_year && (entry.wp_month < gameState.current_wp_month || (entry.wp_month === gameState.current_wp_month && entry.wp_week <= gameState.current_wp_week))))) : pendingEntries;
  const catalogOptions: ActualRaceCatalogOption[] = catalogs ?? [];

  return <main className="mx-auto w-full max-w-7xl px-4 py-8 sm:px-6 sm:py-10">
    <section className="flex flex-col gap-5 border-b border-stone-800 pb-7 lg:flex-row lg:items-end lg:justify-between">
      <div><p className="text-sm font-semibold tracking-[0.24em] text-amber-300">GM · 赛果录入</p><h1 className="mt-3 text-3xl font-semibold tracking-tight">赛果管理</h1><p className="mt-3 max-w-3xl text-sm leading-6 text-stone-400">以实际比赛为中心录入 Winning Post 赛果。赛前确认赛程、实际比赛与赛果是三个独立事实；计划与实际可以不同。</p></div>
      <div className="rounded-xl border border-amber-300/30 bg-amber-300/5 px-5 py-4 text-sm"><p className="text-stone-500">当前 Winning Post 时间</p><p className="mt-1 font-semibold text-amber-100">{gameState ? formatWpTime(gameState.current_wp_year, gameState.current_wp_month, gameState.current_wp_week) : "尚未初始化"}</p></div>
    </section>
    <Notice message={notice} />
    {dataError && <p className="mt-5 rounded-xl border border-red-400/40 bg-red-400/5 p-4 text-sm leading-6 text-red-100">部分赛果管理数据暂时无法读取。请刷新；页面不会显示数据库内部错误。</p>}

    <section className="mt-8 grid gap-6 xl:grid-cols-[minmax(20rem,0.85fr)_minmax(0,1.15fr)]">
      <section className="rounded-xl border border-stone-800 bg-stone-900 p-6"><h2 className="text-xl font-semibold text-amber-200">新建实际比赛</h2><p className="mt-2 text-sm leading-6 text-stone-400">实际比赛必须由 GM 明确创建。比赛目录会保存名称和分级历史快照；已停用目录也可用于历史补录。</p>{gameState ? <div className="mt-5"><ActualRaceForm action={createActualRace} catalogs={catalogOptions} currentWp={{ year: gameState.current_wp_year, month: gameState.current_wp_month, week: gameState.current_wp_week }} pendingLabel="正在创建…" submitLabel="创建实际比赛" /></div> : <p className="mt-5 rounded-lg border border-amber-300/30 bg-amber-300/5 p-4 text-sm text-amber-100">请先初始化游戏时间。</p>}</section>
      <section className="grid gap-4 sm:grid-cols-2"><article className="rounded-xl border border-stone-800 bg-stone-900 p-6"><p className="text-sm text-stone-500">实际比赛</p><p className="mt-2 text-3xl font-semibold text-amber-100">{actualRaces?.length ?? 0}</p><p className="mt-2 text-sm leading-6 text-stone-400">每场实际比赛可关联多匹玩家马匹的赛果。</p></article><article className="rounded-xl border border-stone-800 bg-stone-900 p-6"><p className="text-sm text-stone-500">待录赛果</p><p className="mt-2 text-3xl font-semibold text-amber-100">{overdueEntries.length}</p><p className="mt-2 text-sm leading-6 text-stone-400">已到当前周但尚无有效赛果的已确认赛程。</p></article><article className="rounded-xl border border-stone-800 bg-stone-900 p-6 sm:col-span-2"><p className="text-sm text-stone-500">已录当前有效赛果</p><p className="mt-2 text-3xl font-semibold text-emerald-200">{(results ?? []).filter((result) => result.status === "CONFIRMED").length}</p><p className="mt-2 text-sm leading-6 text-stone-400">赏金目前仅是 Winning Post 赛果事实，不会改变马主资金或产生奖金应收。</p></article></section>
    </section>

    <section className="mt-10"><div className="flex items-end justify-between gap-4"><div><h2 className="text-2xl font-semibold text-amber-200">实际比赛</h2><p className="mt-2 text-sm text-stone-400">按实际 WP 时间最近优先。进入详情后可批量关联并录入多匹马的赛果。</p></div><span className="font-mono text-sm text-stone-500">{actualRaces?.length ?? 0} 场</span></div><div className="mt-5 grid gap-4 lg:grid-cols-2">{(actualRaces ?? []).map((race) => <Link className="rounded-xl border border-stone-800 bg-stone-900 p-5 transition hover:border-amber-300/60" href={`/admin/race-results/${race.id}`} key={race.id}><div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between"><div><p className="font-semibold text-stone-100">{race.race_name} {race.grade && <span className="ml-2 rounded border border-amber-300/35 px-2 py-0.5 text-xs text-amber-100">{formatRaceGrade(race.grade)}</span>}</p><p className="mt-2 text-sm text-stone-400">{formatWpTime(race.wp_year, race.wp_month, race.wp_week)} · {formatRaceKind(race.race_kind)}</p></div><span className="w-fit rounded-full border border-emerald-400/35 px-3 py-1 text-xs text-emerald-100">{resultCountByActualRace.get(race.id) ?? 0} 条有效赛果</span></div><p className="mt-4 text-xs text-stone-500">创建于 {formatDateTime(race.created_at)} · {race.race_catalog_id ? "比赛目录快照" : "自定义比赛"}</p></Link>)}{!actualRaces?.length && <p className="rounded-xl border border-stone-800 bg-stone-900 p-6 text-sm text-stone-500">暂无已记录的实际比赛。</p>}</div></section>

    <section className="mt-10 grid gap-8 xl:grid-cols-2"><section><h2 className="text-xl font-semibold text-amber-200">待录赛果的已确认赛程</h2><p className="mt-2 text-sm text-stone-400">这是提醒而非自动匹配；进入某场实际比赛后由 GM 明确选择关联。</p><div className="mt-5 space-y-3">{overdueEntries.slice(0, 10).map((entry) => <article className="rounded-xl border border-stone-800 bg-stone-900 p-4" key={entry.id}><p className="font-semibold text-stone-100">{formatHorseName(horseById.get(entry.horse_id))} <span className="font-mono text-xs text-stone-500">#{horseById.get(entry.horse_id)?.horse_number ?? "—"}</span></p><p className="mt-1 text-sm text-stone-400">马主：{ownerNameById.get(entry.owner_id) ?? "未知马主"} · {formatWpTime(entry.wp_year, entry.wp_month, entry.wp_week)}</p><p className="mt-2 text-sm text-amber-100">{entry.race_label || (entry.race_catalog_id ? catalogNameById.get(entry.race_catalog_id) ?? "固定比赛" : formatRaceKind(entry.race_kind))}</p></article>)}{!overdueEntries.length && <p className="rounded-xl border border-stone-800 bg-stone-900 p-6 text-sm text-stone-500">当前没有待录的历史赛果。</p>}</div></section><section><h2 className="text-xl font-semibold text-amber-200">最近已录赛果</h2><p className="mt-2 text-sm text-stone-400">当前有效赛果与作废历史在实际比赛详情中分别呈现。</p><div className="mt-5 space-y-3">{(results ?? []).filter((result) => result.status === "CONFIRMED").slice(0, 10).map((result) => <Link className="block rounded-xl border border-stone-800 bg-stone-900 p-4 hover:border-amber-300/60" href={`/admin/race-results/${result.actual_race_id}`} key={result.id}><p className="font-semibold text-stone-100">{formatHorseName(horseById.get(result.horse_id))} · {result.finish_position} 着 · {result.prize_amount}</p><p className="mt-1 text-sm text-stone-400">{formatDateTime(result.recorded_at)}</p></Link>)}{!(results ?? []).some((result) => result.status === "CONFIRMED") && <p className="rounded-xl border border-stone-800 bg-stone-900 p-6 text-sm text-stone-500">暂无已录赛果。</p>}</div></section></section>
  </main>;
}
