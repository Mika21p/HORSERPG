import Link from "next/link";

import { createHorse } from "@/app/admin/actions";
import { HorseForm } from "@/components/horse-form";
import { requireGM } from "@/lib/auth/session";

export default async function NewHorsePage() {
  const { supabase } = await requireGM();
  const { data: owners } = await supabase.from("owners").select("id, display_name").order("display_name");

  return (
    <main className="mx-auto w-full max-w-4xl px-6 py-10">
      <Link className="text-sm text-amber-200 hover:text-amber-100" href="/admin/horses">← 马匹管理</Link>
      <h1 className="mt-5 text-3xl font-semibold tracking-tight">创建马匹</h1>
      <section className="mt-6 rounded-xl border border-stone-800 bg-stone-900 p-6"><HorseForm action={createHorse} owners={owners ?? []} /></section>
    </main>
  );
}
