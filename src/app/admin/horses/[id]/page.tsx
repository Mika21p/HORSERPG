import Link from "next/link";
import { notFound } from "next/navigation";

import { addHorseFactor, deleteHorseFactor, updateHorse } from "@/app/admin/actions";
import { BreedingCandidateControls } from "@/components/breeding-candidate-controls";
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
  const parentIds = [horse.sire_horse_id, horse.dam_horse_id].filter((parentId): parentId is string => Boolean(parentId));
  const [{ data: candidate }, { data: parents }] = await Promise.all([
    supabase
      .from("breeding_candidates")
      .select("candidate_type, is_active, notes")
      .eq("horse_id", id)
      .maybeSingle(),
    parentIds.length
      ? supabase.from("horses").select("id, horse_number, foal_name, name_katakana, translated_name").in("id", parentIds)
      : Promise.resolve({ data: [] }),
  ]);
  const parentById = new Map((parents ?? []).map((parent) => [parent.id, parent]));
  const sireCount = (factors ?? []).filter((factor) => factor.factor_kind === "SIRE").length;
  const mareCount = (factors ?? []).filter((factor) => factor.factor_kind === "MARE").length;
  const sourceLabel = (source: string | null) => source === "INTERNAL" ? "内部 Horse" : source === "REFERENCE" ? "外部资料" : source === "MANUAL" ? "手动" : "历史文本";
  const parentName = (parent: { id: string; horse_number: string | number; foal_name: string; name_katakana: string | null; translated_name: string | null } | undefined, snapshot: string | null) => (
    parent ? <Link className="text-amber-200 hover:text-amber-100" href={`/admin/horses/${parent.id}`}>{snapshot || parent.name_katakana || parent.translated_name || parent.foal_name} <span className="text-xs text-stone-500">#{parent.horse_number}</span></Link> : snapshot || "—"
  );

  return (
    <main className="mx-auto w-full max-w-4xl px-6 py-10">
      <Link className="text-sm text-amber-200 hover:text-amber-100" href="/admin/horses">← Horses</Link>
      <h1 className="mt-5 text-3xl font-semibold tracking-tight">{horse.foal_name}</h1>
      <Notice message={notice} />
      <section className="mt-6 rounded-xl border border-stone-800 bg-stone-900 p-6"><HorseForm action={updateHorse.bind(null, horse.id)} horse={horse} owners={owners ?? []} /></section>
      <section className="mt-8 rounded-xl border border-stone-800 bg-stone-900 p-6">
        <h2 className="text-xl font-semibold text-amber-200">血统事实</h2>
        <p className="mt-2 text-sm leading-6 text-stone-400">新结构化幼驹保留创建时的父母快照；链接只用于导航，不会使用父母当前资料替换本 Horse 的历史名称。</p>
        <dl className="mt-5 grid gap-4 sm:grid-cols-2">
          <div><dt className="text-xs text-stone-500">父马</dt><dd className="mt-1 text-stone-100">{parentName(parentById.get(horse.sire_horse_id ?? ""), horse.sire_name)}</dd></div>
          <div><dt className="text-xs text-stone-500">父系</dt><dd className="mt-1 text-stone-100">{horse.sire_line || "—"}</dd></div>
          <div><dt className="text-xs text-stone-500">母马</dt><dd className="mt-1 text-stone-100">{parentName(parentById.get(horse.dam_horse_id ?? ""), horse.dam_name)}</dd></div>
          <div><dt className="text-xs text-stone-500">母父</dt><dd className="mt-1 text-stone-100">{horse.broodmare_sire_name || "—"}</dd></div>
        </dl>
        {(horse.sire_parent_source_type || horse.dam_parent_source_type) && <div className="mt-5 rounded-lg border border-stone-800 bg-stone-950/60 p-4 text-sm text-stone-400"><p>父马来源：<span className="text-stone-200">{sourceLabel(horse.sire_parent_source_type)}</span>{horse.sire_reference_id && <Link className="ml-2 text-amber-200 hover:text-amber-100" href="/admin/breeding?tab=references">查看外部资料</Link>}</p><p className="mt-2">母马来源：<span className="text-stone-200">{sourceLabel(horse.dam_parent_source_type)}</span>{horse.dam_reference_id && <Link className="ml-2 text-amber-200 hover:text-amber-100" href="/admin/breeding?tab=references">查看外部资料</Link>}</p></div>}
      </section>
      <section className="mt-8 rounded-xl border border-stone-800 bg-stone-900 p-6">
        <h2 className="text-xl font-semibold text-amber-200">繁育候选</h2>
        <p className="mt-2 text-sm leading-6 text-stone-400">仅已退役的 MALE / FEMALE Horse 可成为候选。候选状态不会改变 Horse 生命周期，也不会使用 BREEDING life stage。</p>
        <BreedingCandidateControls candidate={candidate ? { candidateType: candidate.candidate_type as "STALLION" | "BROODMARE", isActive: candidate.is_active, notes: candidate.notes } : null} horseId={horse.id} lifeStage={horse.life_stage} sex={horse.sex} />
      </section>
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
