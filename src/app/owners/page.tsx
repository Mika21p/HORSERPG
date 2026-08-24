import Link from "next/link";

import { AppShell } from "@/components/app-shell";
import { EmptyState, PageHeader, StatusBadge } from "@/components/ui/primitives";
import { requireUser } from "@/lib/auth/session";

export const dynamic = "force-dynamic";

export default async function OwnersPage() {
  const { supabase, user, profile } = await requireUser();
  const { data: owners } = await supabase.from("owners").select("id, display_name, created_at").order("display_name");

  return (
    <AppShell email={user.email} isGM={profile?.role === "GM"}>
      <main className="page-wrap">
        <PageHeader
          action={<StatusBadge>{owners?.length ?? 0} 位 Owner</StatusBadge>}
          description="跑团中的公开马主名录。资金、秘密报价和私密 GM 评价仍遵循原有权限规则。"
          eyebrow="OWNERS DIRECTORY"
          title="马主名录"
        />
        {owners?.length ? (
          <div className="mt-7 grid gap-4 sm:grid-cols-2 xl:grid-cols-3">
            {owners.map((owner, index) => (
              <Link className="group relative overflow-hidden rounded-2xl border border-[#d8d0c2] bg-[#fffcf6] p-5 shadow-[0_10px_30px_rgb(57_47_31/5%)] hover:-translate-y-0.5 hover:border-[#b58a3c]" href={`/owners/${owner.id}`} key={owner.id}>
                <span className="absolute right-4 top-3 font-mono text-4xl font-semibold text-[#173f35]/[0.06]">{String(index + 1).padStart(2, "0")}</span>
                <p className="text-[0.66rem] font-bold uppercase tracking-[0.18em] text-[#9a7131]">Registered Owner</p>
                <h2 className="display-title mt-3 text-2xl font-semibold text-[#173f35]">{owner.display_name}</h2>
                <p className="mt-4 text-sm font-medium text-[#68736c] group-hover:text-[#7d5b24]">查看公开档案 →</p>
              </Link>
            ))}
          </div>
        ) : <EmptyState className="mt-7">尚无公开 Owner。</EmptyState>}
      </main>
    </AppShell>
  );
}
