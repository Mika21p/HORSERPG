import Link from "next/link";

import { createOwner } from "@/app/admin/actions";
import { Notice } from "@/components/notice";
import { requireGM } from "@/lib/auth/session";

type PageProps = {
  searchParams: Promise<{ notice?: string }>;
};

export default async function AdminOwnersPage({ searchParams }: PageProps) {
  const [{ supabase }, { notice }] = await Promise.all([requireGM(), searchParams]);
  const { data: owners } = await supabase
    .from("owners")
    .select("id, display_name, initial_funds, created_at")
    .order("created_at", { ascending: false });

  return (
    <main className="mx-auto grid w-full max-w-6xl gap-8 px-6 py-10 lg:grid-cols-[minmax(0,1fr)_22rem]">
      <section>
        <h1 className="text-3xl font-semibold tracking-tight">Owners</h1>
        <p className="mt-3 text-stone-400">公开资料只维护名称；初始资金创建后不可在此直接改写。</p>
        <Notice message={notice} />
        <div className="mt-6 overflow-hidden rounded-xl border border-stone-800">
          <table className="w-full text-left text-sm">
            <thead className="bg-stone-900 text-stone-400">
              <tr>
                <th className="px-4 py-3 font-medium">名称</th>
                <th className="px-4 py-3 font-medium">初始资金</th>
                <th className="px-4 py-3" />
              </tr>
            </thead>
            <tbody className="divide-y divide-stone-800 bg-stone-950/50">
              {(owners ?? []).map((owner) => (
                <tr key={owner.id}>
                  <td className="px-4 py-3 text-stone-100">{owner.display_name}</td>
                  <td className="px-4 py-3 font-mono text-stone-300">{owner.initial_funds}</td>
                  <td className="px-4 py-3 text-right">
                    <Link className="text-amber-200 hover:text-amber-100" href={`/admin/owners/${owner.id}`}>
                      查看 / 编辑
                    </Link>
                  </td>
                </tr>
              ))}
              {!owners?.length && (
                <tr>
                  <td className="px-4 py-8 text-stone-500" colSpan={3}>
                    尚未创建 Owner。
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
      </section>
      <section className="h-fit rounded-xl border border-stone-800 bg-stone-900 p-5">
        <h2 className="font-semibold text-amber-200">创建 Owner</h2>
        <form action={createOwner} className="mt-5 space-y-4">
          <label className="block text-sm text-stone-300" htmlFor="display_name">
            名称
            <input className="admin-input" id="display_name" name="display_name" required />
          </label>
          <label className="block text-sm text-stone-300" htmlFor="initial_funds">
            初始资金（bigint）
            <input className="admin-input" id="initial_funds" min="0" name="initial_funds" required step="1" type="number" />
          </label>
          <p className="text-xs leading-5 text-stone-500">创建后不可直接修改；后续资金调整需通过未来的流水模块。</p>
          <button className="admin-button w-full">创建 Owner</button>
        </form>
      </section>
    </main>
  );
}
