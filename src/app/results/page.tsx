import Link from "next/link";

import { AppShell } from "@/components/app-shell";
import { requireUser } from "@/lib/auth/session";
import { formatGameMoney, formatHorseName, formatRaceGrade, formatWpTime } from "@/lib/format";

export const dynamic = "force-dynamic";

type PublicResult = {
  race_result_id: string;
  actual_race_id: string;
  horse_id: string;
  owner_id: string;
  wp_year: number;
  wp_month: number;
  wp_week: number;
  race_name: string;
  grade: string | null;
  finish_position: number;
  prize_amount: string;
  actual_jockey: string | null;
  actual_running_style: string | null;
};

export default async function ResultsPage() {
  const { supabase, user, profile } = await requireUser();
  const [{ data: results, error: resultError }, { data: horses, error: horseError }, { data: owners, error: ownerError }] = await Promise.all([
    supabase.from("race_results_public").select("race_result_id, actual_race_id, horse_id, owner_id, wp_year, wp_month, wp_week, race_name, grade, finish_position, prize_amount, actual_jockey, actual_running_style").order("wp_year", { ascending: false }).order("wp_month", { ascending: false }).order("wp_week", { ascending: false }).order("recorded_at", { ascending: false }),
    supabase.from("horses").select("id, horse_number, foal_name, translated_name").order("horse_number"),
    supabase.from("owners").select("id, display_name").order("display_name"),
  ]);
  const dataError = resultError || horseError || ownerError;
  const horseById = new Map((horses ?? []).map((horse) => [horse.id, horse]));
  const ownerNames = new Map((owners ?? []).map((owner) => [owner.id, owner.display_name]));
  const publicResults = (results ?? []) as PublicResult[];
  const groups = new Map<string, PublicResult[]>();
  for (const result of publicResults) groups.set(result.actual_race_id, [...(groups.get(result.actual_race_id) ?? []), result]);
  const ownResults = profile?.owner_id ? publicResults.filter((result) => result.owner_id === profile.owner_id) : [];

  return <AppShell email={user.email} isGM={profile?.role === "GM"}><main className="mx-auto w-full max-w-6xl px-4 py-8 sm:px-6 sm:py-10"><section className="border-b border-stone-800 pb-7"><p className="text-sm font-semibold tracking-[0.22em] text-amber-300">公开赛果</p><h1 className="mt-3 text-3xl font-semibold">比赛结果</h1><p className="mt-3 max-w-3xl text-sm leading-6 text-stone-400">公开显示当前有效的 Winning Post 实际赛果。作废赛果、GM 备注、操作人和赛前内部来源不会出现在这里；比赛赏金不代表马主当前已结算资金。</p></section>{dataError && <p className="mt-5 rounded-xl border border-red-400/40 bg-red-400/5 p-4 text-sm text-red-100">公开赛果暂时无法读取。请刷新；页面不会显示数据库内部错误。</p>}
    {profile?.role === "PLAYER" && <section className="mt-8"><div><h2 className="text-xl font-semibold text-amber-200">我的赛果</h2><p className="mt-2 text-sm text-stone-400">仅按当前登录玩家绑定的马主过滤；不会显示私密报名或 GM 信息。</p></div><div className="mt-5 grid gap-4 md:grid-cols-2">{ownResults.map((result) => <ResultRow horse={horseById.get(result.horse_id)} key={result.race_result_id} result={result} showOwner={false} />)}{!ownResults.length && <p className="rounded-xl border border-stone-800 bg-stone-900 p-5 text-sm text-stone-500">你的马主暂无公开比赛结果。</p>}</div></section>}
    <section className="mt-10"><div><h2 className="text-xl font-semibold text-amber-200">全部公开赛果</h2><p className="mt-2 text-sm text-stone-400">按实际比赛分组；同场多匹玩家马匹会一起显示。</p></div><div className="mt-5 space-y-6">{Array.from(groups.values()).map((group) => { const race = group[0]; return <section className="rounded-xl border border-stone-800 bg-stone-900 p-5 sm:p-6" key={race.actual_race_id}><div className="flex flex-col gap-3 border-b border-stone-800 pb-4 sm:flex-row sm:items-start sm:justify-between"><div><p className="font-semibold text-stone-100">{race.race_name} {race.grade && <span className="ml-2 rounded border border-amber-300/35 px-2 py-0.5 text-xs text-amber-100">{formatRaceGrade(race.grade)}</span>}</p><p className="mt-2 text-sm text-stone-400">{formatWpTime(race.wp_year, race.wp_month, race.wp_week)}</p></div><span className="font-mono text-sm text-stone-500">{group.length} 匹玩家马匹</span></div><div className="mt-4 grid gap-4 md:grid-cols-2">{group.map((result) => <ResultRow horse={horseById.get(result.horse_id)} key={result.race_result_id} ownerName={ownerNames.get(result.owner_id)} result={result} />)}</div></section>; })}{!publicResults.length && <p className="rounded-xl border border-stone-800 bg-stone-900 p-6 text-sm text-stone-500">暂无比赛结果。</p>}</div></section></main></AppShell>;
}

function ResultRow({ result, horse, ownerName, showOwner = true }: { result: PublicResult; horse: { id: string; horse_number: number; foal_name: string; translated_name: string | null } | undefined; ownerName?: string; showOwner?: boolean }) {
  return <article className="rounded-lg border border-stone-800 bg-stone-950/50 p-4"><div className="flex items-start justify-between gap-3"><div><Link className="font-semibold text-stone-100 hover:text-amber-100" href={`/horses/${result.horse_id}`}>{formatHorseName(horse)}</Link><p className="mt-1 font-mono text-xs text-stone-500">#{horse?.horse_number ?? "—"}</p>{showOwner && <p className="mt-2 text-sm text-stone-400">Owner：{ownerName ?? "Owner"}</p>}</div><span className="rounded-full border border-amber-300/40 bg-amber-300/5 px-3 py-1 text-sm font-semibold text-amber-100">{result.finish_position} 着</span></div><div className="mt-4 grid gap-2 text-sm sm:grid-cols-3"><div><p className="text-xs text-stone-500">比赛赏金总额</p><p className="mt-1 font-semibold text-stone-100">{formatGameMoney(result.prize_amount)}</p></div><div><p className="text-xs text-stone-500">实际骑手</p><p className="mt-1 text-stone-200">{result.actual_jockey || "未指定"}</p></div><div><p className="text-xs text-stone-500">实际跑法</p><p className="mt-1 text-stone-200">{result.actual_running_style || "未指定"}</p></div></div></article>;
}
