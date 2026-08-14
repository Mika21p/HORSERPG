import Link from "next/link";
import { notFound } from "next/navigation";

import { AppShell } from "@/components/app-shell";
import { requireUser } from "@/lib/auth/session";

type PageProps = { params: Promise<{ id: string }> };

export default async function HorsePage({ params }: PageProps) {
  const [{ id }, { supabase, user, profile }] = await Promise.all([params, requireUser()]);
  const [{ data: horse }, { data: factors }] = await Promise.all([
    supabase.from("horses").select("*").eq("id", id).maybeSingle(),
    supabase.from("horse_factors").select("factor_kind, factor_name").eq("horse_id", id).order("created_at"),
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
        </section>
      </main>
    </AppShell>
  );
}
