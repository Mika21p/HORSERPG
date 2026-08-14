import Link from "next/link";

import { requireGM } from "@/lib/auth/session";

export default async function AdminHorsesPage() {
  const { supabase } = await requireGM();
  const [{ data: horses }, { data: owners }] = await Promise.all([
    supabase.from("horses").select("id, horse_number, foal_name, owner_id, life_stage").order("horse_number"),
    supabase.from("owners").select("id, display_name"),
  ]);
  const ownerNames = new Map((owners ?? []).map((owner) => [owner.id, owner.display_name]));

  return (
    <main className="mx-auto w-full max-w-6xl px-6 py-10">
      <div className="flex items-end justify-between gap-4">
        <div><h1 className="text-3xl font-semibold tracking-tight">Horses</h1><p className="mt-3 text-stone-400">维护当前 Core Schema 中的 Horse 字段。</p></div>
        <Link className="admin-button" href="/admin/horses/new">创建 Horse</Link>
      </div>
      <div className="mt-6 overflow-hidden rounded-xl border border-stone-800">
        <table className="w-full text-left text-sm">
          <thead className="bg-stone-900 text-stone-400"><tr><th className="px-4 py-3">马号</th><th className="px-4 py-3">名称</th><th className="px-4 py-3">Owner</th><th className="px-4 py-3">阶段</th><th className="px-4 py-3" /></tr></thead>
          <tbody className="divide-y divide-stone-800 bg-stone-950/50">
            {(horses ?? []).map((horse) => <tr key={horse.id}><td className="px-4 py-3 font-mono">{horse.horse_number}</td><td className="px-4 py-3">{horse.foal_name}</td><td className="px-4 py-3 text-stone-400">{horse.owner_id ? ownerNames.get(horse.owner_id) ?? "已归属" : "未归属"}</td><td className="px-4 py-3 text-amber-200">{horse.life_stage}</td><td className="px-4 py-3 text-right"><Link className="text-amber-200 hover:text-amber-100" href={`/admin/horses/${horse.id}`}>编辑</Link></td></tr>)}
            {!horses?.length && <tr><td className="px-4 py-8 text-stone-500" colSpan={5}>尚未创建 Horse。</td></tr>}
          </tbody>
        </table>
      </div>
    </main>
  );
}
