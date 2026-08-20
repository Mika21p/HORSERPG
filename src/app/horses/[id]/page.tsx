import Link from "next/link";
import { notFound } from "next/navigation";

import { AppShell } from "@/components/app-shell";
import { requireUser } from "@/lib/auth/session";
import { formatGameMoney, formatRaceGrade, formatWpTime } from "@/lib/format";

type PageProps = { params: Promise<{ id: string }> };

export default async function HorsePage({ params }: PageProps) {
  const [{ id }, { supabase, user, profile }] = await Promise.all([params, requireUser()]);
  const [{ data: horse }, { data: factors }, { data: publicResults }] = await Promise.all([
    supabase.from("horses").select("*").eq("id", id).maybeSingle(),
    supabase.from("horse_factors").select("factor_kind, factor_name").eq("horse_id", id).order("created_at"),
    supabase.from("race_results_public").select("race_result_id, actual_race_id, wp_year, wp_month, wp_week, race_name, grade, finish_position, prize_amount, actual_jockey, actual_running_style, recorded_at").eq("horse_id", id).order("wp_year", { ascending: false }).order("wp_month", { ascending: false }).order("wp_week", { ascending: false }).order("recorded_at", { ascending: false }),
  ]);

  if (!horse) { notFound(); }
  const { data: owner } = horse.owner_id
    ? await supabase.from("owners").select("id, display_name").eq("id", horse.owner_id).maybeSingle()
    : { data: null };

  const fields = [
    ["马号", horse.horse_number],
    ["出生年", horse.birth_year],
    ["性别", horse.sex],
    ["毛色", horse.coat_color],
    ["父", horse.sire_name],
    ["父系", horse.sire_line],
    ["母父", horse.broodmare_sire_name],
    ["骑手", horse.current_jockey_name ?? "—"],
    ["调教师", horse.current_trainer_name ?? "—"],
    ["生命周期", horse.life_stage],
    ["Owner", owner?.display_name ?? "未归属"],
  ];
  const results = publicResults ?? [];
  const wins = results.filter((result) => result.finish_position === 1);
  const g1Wins = wins.filter((result) => result.grade === "G1");
  const totalPrize = results.reduce((sum, result) => sum + BigInt(result.prize_amount), BigInt(0));

  return (
    <AppShell email={user.email} isGM={profile?.role === "GM"}>
      <main className="mx-auto w-full max-w-4xl px-6 py-10">
        <Link className="text-sm text-amber-200 hover:text-amber-100" href="/horses">← Horses</Link>
        <section className="mt-5 rounded-xl border border-stone-800 bg-stone-900 p-7">
          <p className="text-sm font-semibold tracking-[0.18em] text-amber-300">HORSE #{horse.horse_number}</p>
          <h1 className="mt-3 text-3xl font-semibold">{horse.translated_name || horse.foal_name}</h1>
          {horse.name_katakana && <p className="mt-2 text-stone-400">{horse.name_katakana}</p>}
          <dl className="mt-8 grid gap-5 sm:grid-cols-2">
            {fields.map(([label, value]) => <div key={label}><dt className="text-xs font-medium tracking-wide text-stone-500">{label}</dt><dd className="mt-1 text-stone-100">{value}</dd></div>)}
          </dl>
          <div className="mt-8 border-t border-stone-800 pt-6">
            <h2 className="font-semibold text-amber-200">Horse Factors</h2>
            <div className="mt-3 flex flex-wrap gap-2">
              {(factors ?? []).map((factor) => <span className="rounded-full border border-stone-700 px-3 py-1 text-sm text-stone-300" key={`${factor.factor_kind}-${factor.factor_name}`}><span className="mr-1 text-xs text-amber-300">{factor.factor_kind}</span>{factor.factor_name}</span>)}
              {!factors?.length && <p className="text-sm text-stone-500">尚未记录 Horse Factor。</p>}
            </div>
          </div>
          <div className="mt-8 border-t border-stone-800 pt-6">
            <h2 className="font-semibold text-amber-200">战绩</h2>
            <p className="mt-2 text-sm leading-6 text-stone-400">仅按当前有效公开赛果派生。比赛获得赏金总额不代表 Owner 当前已结算资金；VOIDED 赛果不计入。</p>
            <dl className="mt-5 grid gap-3 sm:grid-cols-2 lg:grid-cols-4"><div className="rounded-lg border border-stone-800 bg-stone-950/60 p-4"><dt className="text-xs text-stone-500">出赛数</dt><dd className="mt-2 text-2xl font-semibold text-stone-100">{results.length}</dd></div><div className="rounded-lg border border-stone-800 bg-stone-950/60 p-4"><dt className="text-xs text-stone-500">胜场</dt><dd className="mt-2 text-2xl font-semibold text-stone-100">{wins.length}</dd></div><div className="rounded-lg border border-stone-800 bg-stone-950/60 p-4"><dt className="text-xs text-stone-500">G1 胜场</dt><dd className="mt-2 text-2xl font-semibold text-stone-100">{g1Wins.length}</dd></div><div className="rounded-lg border border-stone-800 bg-stone-950/60 p-4"><dt className="text-xs text-stone-500">比赛获得赏金总额</dt><dd className="mt-2 break-all text-lg font-semibold text-amber-100">{formatGameMoney(totalPrize)}</dd></div></dl>
            {g1Wins.length > 0 && <div className="mt-6"><h3 className="text-sm font-semibold text-amber-100">G1 胜鞍</h3><div className="mt-3 grid gap-3 sm:grid-cols-2">{g1Wins.map((result) => <article className="rounded-lg border border-amber-300/25 bg-amber-300/5 p-4" key={result.race_result_id}><p className="font-medium text-stone-100">{result.race_name}</p><p className="mt-1 text-sm text-stone-400">{formatWpTime(result.wp_year, result.wp_month, result.wp_week)} · {formatRaceGrade(result.grade)}</p></article>)}</div></div>}
            <div className="mt-6 space-y-3">{results.map((result) => <article className="rounded-lg border border-stone-800 bg-stone-950/50 p-4" key={result.race_result_id}><div className="flex flex-col gap-2 sm:flex-row sm:items-start sm:justify-between"><div><p className="font-medium text-stone-100">{result.race_name} {result.grade && <span className="ml-2 text-xs text-amber-100">{formatRaceGrade(result.grade)}</span>}</p><p className="mt-1 text-sm text-stone-400">{formatWpTime(result.wp_year, result.wp_month, result.wp_week)} · 骑手：{result.actual_jockey || "未指定"} · 跑法：{result.actual_running_style || "未指定"}</p></div><p className="font-semibold text-amber-100">{result.finish_position} 着 · {formatGameMoney(result.prize_amount)}</p></div></article>)}{!results.length && <p className="rounded-lg border border-stone-800 bg-stone-950/60 p-5 text-sm text-stone-500">暂无正式比赛记录。</p>}</div>
          </div>
        </section>
      </main>
    </AppShell>
  );
}
