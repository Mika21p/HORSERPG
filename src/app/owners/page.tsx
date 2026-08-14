import Link from "next/link";

import { AppShell } from "@/components/app-shell";
import { requireUser } from "@/lib/auth/session";

export const dynamic = "force-dynamic";

export default async function OwnersPage() {
  const { supabase, user, profile } = await requireUser();
  const { data: owners } = await supabase
    .from("owners")
    .select("id, display_name, created_at")
    .order("display_name");

  return (
    <AppShell email={user.email} isGM={profile?.role === "GM"}>
      <main className="mx-auto w-full max-w-5xl px-6 py-10">
        <h1 className="text-3xl font-semibold tracking-tight">Owners</h1>
        <p className="mt-3 text-stone-400">公开 Owner 名录。</p>
        <div className="mt-6 grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
          {(owners ?? []).map((owner) => (
            <Link className="rounded-xl border border-stone-800 bg-stone-900 p-5 hover:border-amber-300/60" href={`/owners/${owner.id}`} key={owner.id}>
              <h2 className="font-semibold text-stone-100">{owner.display_name}</h2>
              <p className="mt-2 text-sm text-stone-500">查看公开资料</p>
            </Link>
          ))}
          {!owners?.length && <p className="text-stone-500">尚无公开 Owner。</p>}
        </div>
      </main>
    </AppShell>
  );
}
