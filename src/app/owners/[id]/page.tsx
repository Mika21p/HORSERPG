import Link from "next/link";
import { notFound } from "next/navigation";

import { AppShell } from "@/components/app-shell";
import { requireUser } from "@/lib/auth/session";

type PageProps = { params: Promise<{ id: string }> };

export default async function OwnerPage({ params }: PageProps) {
  const [{ id }, { supabase, user, profile }] = await Promise.all([params, requireUser()]);
  const { data: owner } = await supabase
    .from("owners")
    .select("id, display_name, created_at")
    .eq("id", id)
    .maybeSingle();

  if (!owner) {
    notFound();
  }

  return (
    <AppShell email={user.email} isGM={profile?.role === "GM"}>
      <main className="mx-auto w-full max-w-3xl px-6 py-10">
        <Link className="text-sm text-amber-200 hover:text-amber-100" href="/owners">
          ← Owners
        </Link>
        <section className="mt-5 rounded-xl border border-stone-800 bg-stone-900 p-7">
          <p className="text-sm font-semibold tracking-[0.18em] text-amber-300">OWNER</p>
          <h1 className="mt-3 text-3xl font-semibold">{owner.display_name}</h1>
          <p className="mt-5 text-sm leading-6 text-stone-400">第一阶段仅展示 Core Schema 中适合公开的基础资料。</p>
        </section>
      </main>
    </AppShell>
  );
}
