import Link from "next/link";

import { AppShell } from "@/components/app-shell";
import { EmptyState, PageHeader, StatusBadge } from "@/components/ui/primitives";
import { requireUser } from "@/lib/auth/session";
import { formatHorseLifeStage, formatHorseSex } from "@/lib/format";

export const dynamic = "force-dynamic";

export default async function HorsesPage() {
  const { supabase, user, profile } = await requireUser();
  const [{ data: horses }, { data: owners }] = await Promise.all([
    supabase.from("horses").select("id, horse_number, foal_name, translated_name, sex, coat_color, owner_id, life_stage").order("horse_number"),
    supabase.from("owners").select("id, display_name"),
  ]);
  const ownerNames = new Map((owners ?? []).map((owner) => [owner.id, owner.display_name]));

  return (
    <AppShell email={user.email} isGM={profile?.role === "GM"}>
      <main className="page-wrap">
        <PageHeader
          action={<StatusBadge>{horses?.length ?? 0} 匹记录</StatusBadge>}
          description="浏览公开的马匹身份、当前归属与生命周期；进入详情可查看血统、战绩和健康记录。"
          eyebrow="马房档案"
          title="马匹档案"
        />
        {horses?.length ? (
          <div className="table-shell mt-7">
            <table className="responsive-public-table w-full text-left text-sm">
              <thead className="bg-[#ebe5da]/70 text-xs font-bold uppercase tracking-[0.1em] text-[#677069]">
                <tr>
                  <th className="px-5 py-4">马号</th><th className="px-5 py-4">名称</th><th className="px-5 py-4">性别 / 毛色</th><th className="px-5 py-4">马主</th><th className="px-5 py-4">阶段</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-[#d8d0c2]">
                {horses.map((horse) => (
                  <tr className="group hover:bg-[#f7f3eb]" key={horse.id}>
                    <td className="px-5 py-4 font-mono font-semibold text-[#7d5b24]" data-label="马号">#{horse.horse_number}</td>
                    <td className="px-5 py-4" data-label="名称"><Link className="display-title text-lg font-semibold text-[#173f35] hover:text-[#9a7131]" href={`/horses/${horse.id}`}>{horse.translated_name || horse.foal_name}</Link></td>
                    <td className="px-5 py-4 text-[#626d66]" data-label="性别 / 毛色">{formatHorseSex(horse.sex)} / {horse.coat_color}</td>
                    <td className="px-5 py-4 text-[#626d66]" data-label="马主">{horse.owner_id ? ownerNames.get(horse.owner_id) ?? "已归属" : "未归属"}</td>
                    <td className="px-5 py-4" data-label="阶段"><StatusBadge tone={horse.life_stage === "ACTIVE" ? "success" : "neutral"}>{formatHorseLifeStage(horse.life_stage)}</StatusBadge></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        ) : <EmptyState className="mt-7">尚无公开马匹记录。</EmptyState>}
      </main>
    </AppShell>
  );
}
