import Link from "next/link";

import { AppShell } from "@/components/app-shell";
import { requireUser } from "@/lib/auth/session";

export const dynamic = "force-dynamic";

export default async function HorsesPage() {
  const { supabase, user, profile } = await requireUser();
  const [{ data: horses }, { data: owners }] = await Promise.all([
    supabase
      .from("horses")
      .select("id, horse_number, foal_name, translated_name, sex, coat_color, owner_id, life_stage")
      .order("horse_number"),
    supabase.from("owners").select("id, display_name"),
  ]);
  const ownerNames = new Map((owners ?? []).map((owner) => [owner.id, owner.display_name]));

  return (
    <AppShell email={user.email} isGM={profile?.role === "GM"}>
      <main className="mx-auto w-full max-w-6xl px-6 py-10">
        <h1 className="text-3xl font-semibold tracking-tight">Horses</h1>
        <p className="mt-3 text-stone-400">当前公开的 Horse Core 资料。</p>
        <div className="mt-6 overflow-hidden rounded-xl border border-stone-800">
          <table className="w-full text-left text-sm">
            <thead className="bg-stone-900 text-stone-400"><tr><th className="px-4 py-3">马号</th><th className="px-4 py-3">名称</th><th className="px-4 py-3">性别 / 毛色</th><th className="px-4 py-3">Owner</th><th className="px-4 py-3">阶段</th></tr></thead>
            <tbody className="divide-y divide-stone-800 bg-stone-950/50">
              {(horses ?? []).map((horse) => (
                <tr key={horse.id}>
                  <td className="px-4 py-3 font-mono text-amber-200">{horse.horse_number}</td>
                  <td className="px-4 py-3"><Link className="hover:text-amber-200" href={`/horses/${horse.id}`}>{horse.translated_name || horse.foal_name}</Link></td>
                  <td className="px-4 py-3 text-stone-400">{horse.sex} / {horse.coat_color}</td>
                  <td className="px-4 py-3 text-stone-400">{horse.owner_id ? ownerNames.get(horse.owner_id) ?? "已归属" : "未归属"}</td>
                  <td className="px-4 py-3 text-stone-400">{horse.life_stage}</td>
                </tr>
              ))}
              {!horses?.length && <tr><td className="px-4 py-8 text-stone-500" colSpan={5}>尚无公开 Horse。</td></tr>}
            </tbody>
          </table>
        </div>
      </main>
    </AppShell>
  );
}
