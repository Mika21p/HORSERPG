import Link from "next/link";
import { notFound } from "next/navigation";

import { correctActualRace } from "@/app/admin/race-results/actions";
import { ActualRaceForm, type ActualRaceCatalogOption } from "@/components/actual-race-form";
import { Notice } from "@/components/notice";
import { RaceResultsWorkbench, type RaceResultCandidate, type RaceResultHistoryItem, type ResultActualRaceOption } from "@/components/race-results-workbench";
import { requireGM } from "@/lib/auth/session";
import { formatDateTime, formatRaceGrade, formatRaceKind, formatWpTime } from "@/lib/format";

type PageProps = { params: Promise<{ actualRaceId: string }>; searchParams: Promise<{ notice?: string }> };

export const dynamic = "force-dynamic";

function timeOrder(year: number, month: number, week: number) {
  return year * 60 + month * 5 + week;
}

export default async function ActualRaceDetailPage({ params, searchParams }: PageProps) {
  const [{ actualRaceId }, { notice }, { supabase }] = await Promise.all([params, searchParams, requireGM()]);
  const [{ data: actualRace, error: actualRaceError }, { data: gameState, error: gameStateError }, { data: catalogs, error: catalogError }, { data: entries, error: entryError }, { data: results, error: resultError }, { data: horses, error: horseError }, { data: owners, error: ownerError }, { data: allActualRaces, error: allActualRaceError }, { data: healthEvents, error: healthEventError }] = await Promise.all([
    supabase.from("actual_races").select("id, wp_year, wp_month, wp_week, race_kind, race_catalog_id, race_name, grade, created_at, updated_at").eq("id", actualRaceId).maybeSingle(),
    supabase.from("game_state").select("current_wp_year, current_wp_month, current_wp_week").maybeSingle(),
    supabase.from("race_catalog").select("id, name, grade, default_wp_month, default_wp_week, is_active").order("name"),
    supabase.from("confirmed_race_entries").select("id, request_id, horse_id, owner_id, wp_year, wp_month, wp_week, race_kind, race_catalog_id, race_label, jockey, running_style, confirmed_at").order("wp_year").order("wp_month").order("wp_week").order("confirmed_at"),
    supabase.from("race_results").select("id, confirmed_race_entry_id, actual_race_id, horse_id, status, finish_position, prize_amount, actual_jockey, actual_running_style, gm_note, recorded_at, voided_at, void_reason").order("recorded_at", { ascending: false }),
    supabase.from("horses").select("id, horse_number, foal_name, translated_name, current_stamina").order("horse_number"),
    supabase.from("owners").select("id, display_name").order("display_name"),
    supabase.from("actual_races").select("id, wp_year, wp_month, wp_week, race_name, grade").order("wp_year", { ascending: false }).order("wp_month", { ascending: false }).order("wp_week", { ascending: false }),
    supabase.from("horse_health_events").select("id, horse_id, race_result_id, event_type, status, event_sequence").order("event_sequence", { ascending: false }),
  ]);

  if (!actualRace && !actualRaceError) notFound();
  const dataError = actualRaceError || gameStateError || catalogError || entryError || resultError || horseError || ownerError || allActualRaceError || healthEventError;
  if (!actualRace || !gameState) return <main className="mx-auto w-full max-w-6xl px-6 py-10"><p className="rounded-xl border border-red-400/40 bg-red-400/5 p-6 text-sm text-red-100">实际比赛资料暂时无法读取。请返回赛果管理后刷新；页面不会显示内部错误。</p></main>;

  const horsesById = new Map((horses ?? []).map((horse) => [horse.id, horse]));
  const ownerNames = new Map((owners ?? []).map((owner) => [owner.id, owner.display_name]));
  const catalogNames = new Map((catalogs ?? []).map((catalog) => [catalog.id, catalog.name]));
  const entriesById = new Map((entries ?? []).map((entry) => [entry.id, entry]));
  const confirmedResultEntryIds = new Set((results ?? []).filter((result) => result.status === "CONFIRMED").map((result) => result.confirmed_race_entry_id));
  const activePostRaceByResultId = new Map((healthEvents ?? []).filter((event) => event.status === "ACTIVE" && event.event_type === "POST_RACE" && event.race_result_id).map((event) => [event.race_result_id as string, event]));
  const latestActiveHealthByHorseId = new Map<string, string>();
  for (const event of healthEvents ?? []) if (event.status === "ACTIVE" && !latestActiveHealthByHorseId.has(event.horse_id)) latestActiveHealthByHorseId.set(event.horse_id, event.id);
  const currentResults = (results ?? []).filter((result) => result.actual_race_id === actualRace.id && result.status === "CONFIRMED");
  const voidedResults = (results ?? []).filter((result) => result.actual_race_id === actualRace.id && result.status === "VOIDED");
  const actualOrder = timeOrder(actualRace.wp_year, actualRace.wp_month, actualRace.wp_week);
  const nowOrder = timeOrder(gameState.current_wp_year, gameState.current_wp_month, gameState.current_wp_week);
  const selectedActualRace = actualRace;

  function entryRaceName(entry: NonNullable<typeof entries>[number]) {
    return entry.race_label || (entry.race_catalog_id ? catalogNames.get(entry.race_catalog_id) ?? "固定比赛" : formatRaceKind(entry.race_kind));
  }

  function toCandidate(entry: NonNullable<typeof entries>[number]): RaceResultCandidate {
    const entryOrder = timeOrder(entry.wp_year, entry.wp_month, entry.wp_week);
    const sameTime = entryOrder === actualOrder;
    const sameRace = entry.race_kind === selectedActualRace.race_kind && (entry.race_kind === "CATALOG" ? entry.race_catalog_id === selectedActualRace.race_catalog_id : (entry.race_label ?? "").trim().toLocaleLowerCase() === selectedActualRace.race_name.trim().toLocaleLowerCase());
    const recommendation: RaceResultCandidate["recommendation"] = entryOrder > nowOrder ? "未来赛程" : sameTime && sameRace ? "强推荐" : sameTime ? "同周候选" : Math.abs(entryOrder - actualOrder) <= 1 ? "相邻周候选" : "其他待录赛程";
    return { id: entry.id, horseId: entry.horse_id, horseName: horsesById.get(entry.horse_id)?.translated_name || horsesById.get(entry.horse_id)?.foal_name || "Horse", horseNumber: horsesById.get(entry.horse_id)?.horse_number ?? "—", ownerName: ownerNames.get(entry.owner_id) ?? "Owner", currentStamina: horsesById.get(entry.horse_id)?.current_stamina ?? null, wpYear: entry.wp_year, wpMonth: entry.wp_month, wpWeek: entry.wp_week, raceKind: entry.race_kind, raceCatalogId: entry.race_catalog_id, raceLabel: entryRaceName(entry), jockey: entry.jockey, runningStyle: entry.running_style, source: entry.request_id ? "PLAYER Request" : "GM Direct", recommendation };
  }

  const candidates = (entries ?? []).filter((entry) => !confirmedResultEntryIds.has(entry.id)).map(toCandidate).sort((left, right) => {
    const rank: Record<RaceResultCandidate["recommendation"], number> = { "强推荐": 0, "同周候选": 1, "相邻周候选": 2, "其他待录赛程": 3, "未来赛程": 4 };
    return rank[left.recommendation] - rank[right.recommendation] || left.wpYear - right.wpYear || left.wpMonth - right.wpMonth || left.wpWeek - right.wpWeek || left.horseName.localeCompare(right.horseName, "zh-CN");
  });

  function toHistory(result: NonNullable<typeof results>[number]): RaceResultHistoryItem | null {
    const entry = entriesById.get(result.confirmed_race_entry_id);
    if (!entry) return null;
    const postRaceEvent = activePostRaceByResultId.get(result.id);
    return { ...toCandidate(entry), resultId: result.id, status: result.status, actualRaceId: result.actual_race_id, finishPosition: result.finish_position, prizeAmount: String(result.prize_amount), actualJockey: result.actual_jockey, actualRunningStyle: result.actual_running_style, gmNote: result.gm_note, recordedAt: result.recorded_at, voidedAt: result.voided_at, voidReason: result.void_reason, postRaceProcessed: Boolean(postRaceEvent), hasLaterActiveHealthEvent: Boolean(postRaceEvent && latestActiveHealthByHorseId.get(result.horse_id) !== postRaceEvent.id) };
  }

  const history = currentResults.map(toHistory).filter((value): value is RaceResultHistoryItem => value !== null);
  const voidHistory = voidedResults.map(toHistory).filter((value): value is RaceResultHistoryItem => value !== null);
  const allRaceOptions: ResultActualRaceOption[] = (allActualRaces ?? []).map((race) => ({ ...race }));
  const catalogsForForm: ActualRaceCatalogOption[] = catalogs ?? [];
  const correctActual = correctActualRace.bind(null, actualRace.id);

  return <main className="mx-auto w-full max-w-7xl px-4 py-8 sm:px-6 sm:py-10"><Link className="text-sm text-amber-200 hover:text-amber-100" href="/admin/race-results">← 赛果管理</Link><section className="mt-5 rounded-xl border border-stone-800 bg-stone-900 p-6 sm:p-7"><div className="flex flex-col gap-4 lg:flex-row lg:items-start lg:justify-between"><div><p className="text-sm font-semibold tracking-[0.2em] text-amber-300">ACTUAL RACE</p><h1 className="mt-3 text-3xl font-semibold">{actualRace.race_name} {actualRace.grade && <span className="ml-2 inline-block rounded border border-amber-300/35 px-2 py-1 align-middle text-sm text-amber-100">{formatRaceGrade(actualRace.grade)}</span>}</h1><p className="mt-3 text-sm text-stone-400">{formatWpTime(actualRace.wp_year, actualRace.wp_month, actualRace.wp_week)} · {formatRaceKind(actualRace.race_kind)} · {actualRace.race_catalog_id ? "Catalog 历史快照" : "非 Catalog 实际比赛"}</p></div><div className="rounded-lg border border-stone-800 bg-stone-950/60 px-4 py-3 text-sm text-stone-400"><p>当前有效赛果：<span className="font-semibold text-emerald-200">{history.length}</span></p><p className="mt-1">VOIDED 历史：<span className="font-semibold text-stone-200">{voidHistory.length}</span></p><p className="mt-2 text-xs">创建于 {formatDateTime(actualRace.created_at)}</p></div></div></section><Notice message={notice} />{dataError && <p className="mt-5 rounded-xl border border-red-400/40 bg-red-400/5 p-4 text-sm leading-6 text-red-100">部分详情数据暂时无法读取。请刷新；不会显示内部错误。</p>}
    <details className="mt-6 rounded-xl border border-amber-300/25 bg-amber-300/5 p-5"><summary className="cursor-pointer text-sm font-semibold text-amber-100">修正 Actual Race</summary><p className="mt-3 text-sm leading-6 text-stone-300">实际比赛纠错会改变所有关联赛果所显示的实际比赛信息，但不会删除或重新创建这些赛果。当前关联 {currentResults.length + voidedResults.length} 条历史结果。</p><div className="mt-5"><ActualRaceForm action={correctActual} catalogs={catalogsForForm} confirmation="确认修正这场 Actual Race 吗？关联 Race Result 将继续指向同一实际比赛记录。" currentWp={{ year: gameState.current_wp_year, month: gameState.current_wp_month, week: gameState.current_wp_week }} defaultValues={{ wpYear: actualRace.wp_year, wpMonth: actualRace.wp_month, wpWeek: actualRace.wp_week, raceKind: actualRace.race_kind, raceCatalogId: actualRace.race_catalog_id, raceLabel: actualRace.race_catalog_id ? null : actualRace.race_name }} includeReason pendingLabel="正在修正…" submitLabel="确认实际比赛纠错" /></div></details>
    <section className="mt-8"><RaceResultsWorkbench actualRace={{ id: actualRace.id, wpYear: actualRace.wp_year, wpMonth: actualRace.wp_month, wpWeek: actualRace.wp_week, raceKind: actualRace.race_kind, raceCatalogId: actualRace.race_catalog_id, raceName: actualRace.race_name, grade: actualRace.grade }} actualRaces={allRaceOptions} candidates={candidates} confirmedResults={history} voidedResults={voidHistory} /></section></main>;
}
