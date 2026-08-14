import Link from "next/link";
import { notFound } from "next/navigation";

import { updateOwner } from "@/app/admin/actions";
import { Notice } from "@/components/notice";
import { requireGM } from "@/lib/auth/session";

type PageProps = {
  params: Promise<{ id: string }>;
  searchParams: Promise<{ notice?: string }>;
};

export default async function AdminOwnerDetailPage({ params, searchParams }: PageProps) {
  const [{ id }, { notice }, { supabase }] = await Promise.all([params, searchParams, requireGM()]);
  const { data: owner } = await supabase
    .from("owners")
    .select("id, display_name, initial_funds, created_at, updated_at")
    .eq("id", id)
    .maybeSingle();

  if (!owner) {
    notFound();
  }

  return (
    <main className="mx-auto w-full max-w-3xl px-6 py-10">
      <Link className="text-sm text-amber-200 hover:text-amber-100" href="/admin/owners">
        ← Owners
      </Link>
      <h1 className="mt-5 text-3xl font-semibold tracking-tight">{owner.display_name}</h1>
      <Notice message={notice} />
      <section className="mt-6 rounded-xl border border-stone-800 bg-stone-900 p-6">
        <dl className="grid gap-4 text-sm sm:grid-cols-2">
          <div>
            <dt className="text-stone-500">初始资金</dt>
            <dd className="mt-1 font-mono text-stone-100">{owner.initial_funds}</dd>
          </div>
          <div>
            <dt className="text-stone-500">创建时间</dt>
            <dd className="mt-1 text-stone-100">{new Date(owner.created_at).toLocaleString("zh-CN")}</dd>
          </div>
        </dl>
        <form action={updateOwner.bind(null, owner.id)} className="mt-8 max-w-md space-y-4 border-t border-stone-800 pt-6">
          <label className="block text-sm text-stone-300" htmlFor="display_name">
            公开名称
            <input className="admin-input" defaultValue={owner.display_name} id="display_name" name="display_name" required />
          </label>
          <p className="text-xs leading-5 text-stone-500">初始资金不会出现在编辑表单中，数据库也会拒绝直接修改。</p>
          <button className="admin-button">保存公开资料</button>
        </form>
      </section>
    </main>
  );
}
