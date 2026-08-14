import Link from "next/link";
import { notFound } from "next/navigation";

import { addHorseFactor, deleteHorseFactor, updateHorse } from "@/app/admin/actions";
import { HorseForm } from "@/components/horse-form";
import { Notice } from "@/components/notice";
import { requireGM } from "@/lib/auth/session";

type PageProps = { params: Promise<{ id: string }>; searchParams: Promise<{ notice?: string }> };

export default async function AdminHorseDetailPage({ params, searchParams }: PageProps) {
  const [{ id }, { notice }, { supabase }] = await Promise.all([params, searchParams, requireGM()]);
  const [{ data: horse }, { data: owners }, { data: factors }] = await Promise.all([
    supabase.from("horses").select("*").eq("id", id).maybeSingle(),
    supabase.from("owners").select("id, display_name").order("display_name"),
    supabase.from("horse_factors").select("id, factor_kind, factor_name").eq("horse_id", id).order("created_at"),
  ]);

  if (!horse) { notFound(); }
  const sireCount = (factors ?? []).filter((factor) => factor.factor_kind === "SIRE").length;
  const mareCount = (factors ?? []).filter((factor) => factor.factor_kind === "MARE").length;

  return (
    <main className="mx-auto w-full max-w-4xl px-6 py-10">
      <Link className="text-sm text-amber-200 hover:text-amber-100" href="/admin/horses">← Horses</Link>
      <h1 className="mt-5 text-3xl font-semibold tracking-tight">{horse.foal_name}</h1>
      <Notice message={notice} />
      <section className="mt-6 rounded-xl border border-stone-800 bg-stone-900 p-6"><HorseForm action={updateHorse.bind(null, horse.id)} horse={horse} owners={owners ?? []} /></section>
      <section className="mt-8 rounded-xl border border-stone-800 bg-stone-900 p-6">
        <h2 className="text-xl font-semibold text-amber-200">Horse Factors</h2>
        <p className="mt-2 text-sm text-stone-400">SIRE {sireCount}/2 · MARE {mareCount}/2。数据库同时强制该上限。</p>
        <div className="mt-5 grid gap-3 sm:grid-cols-2">
          {(factors ?? []).map((factor) => (
            <div className="flex items-center justify-between rounded-lg border border-stone-800 bg-stone-950 px-4 py-3" key={factor.id}>
              <span><span className="mr-2 text-xs font-semibold text-amber-300">{factor.factor_kind}</span>{factor.factor_name}</span>
              <form action={deleteHorseFactor.bind(null, horse.id, factor.id)}><button className="text-sm text-red-300 hover:text-red-200">删除</button></form>
            </div>
          ))}
        </div>
        <form action={addHorseFactor.bind(null, horse.id)} className="mt-6 grid gap-3 border-t border-stone-800 pt-5 sm:grid-cols-[10rem_minmax(0,1fr)_auto]">
          <select className="admin-input" defaultValue="SIRE" name="factor_kind"><option value="SIRE">SIRE</option><option value="MARE">MARE</option></select>
          <input className="admin-input" name="factor_name" placeholder="Factor 名称" required />
          <button className="admin-button">新增 Factor</button>
        </form>
      </section>
    </main>
  );
}
