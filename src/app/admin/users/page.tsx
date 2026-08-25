import Link from "next/link";

import { createPlayer } from "@/app/admin/actions";
import { Notice } from "@/components/notice";
import { requireGM } from "@/lib/auth/session";
import { createAdminClient } from "@/lib/supabase/admin";

type PageProps = { searchParams: Promise<{ notice?: string }> };

export default async function AdminUsersPage({ searchParams }: PageProps) {
  const [{ supabase }, { notice }] = await Promise.all([requireGM(), searchParams]);
  const admin = createAdminClient();
  const [{ data: owners }, { data: profiles }, { data: authUsers }] = await Promise.all([
    supabase.from("owners").select("id, display_name").order("display_name"),
    supabase.from("user_profiles").select("id, role, owner_id, display_name").order("created_at", { ascending: false }),
    admin.auth.admin.listUsers({ page: 1, perPage: 1000 }),
  ]);
  const boundOwnerIds = new Set((profiles ?? []).flatMap((profile) => profile.owner_id ? [profile.owner_id] : []));
  const availableOwners = (owners ?? []).filter((owner) => !boundOwnerIds.has(owner.id));
  const ownerNames = new Map((owners ?? []).map((owner) => [owner.id, owner.display_name]));
  const emailsByUserId = new Map((authUsers?.users ?? []).map((user) => [user.id, user.email]));

  return (
    <main className="mx-auto grid w-full max-w-6xl gap-8 px-6 py-10 lg:grid-cols-[minmax(0,1fr)_24rem]">
      <section>
        <h1 className="text-3xl font-semibold tracking-tight">用户管理</h1>
        <p className="mt-3 text-stone-400">本页只能创建玩家账号；GM 账号需由开发者初始化工具创建。</p>
        <Notice message={notice} />
        <div className="mt-6 overflow-hidden rounded-xl border border-stone-800">
          <table className="w-full text-left text-sm">
            <thead className="bg-stone-900 text-stone-400"><tr><th className="px-4 py-3">角色</th><th className="px-4 py-3">显示名</th><th className="px-4 py-3">登录邮箱</th><th className="px-4 py-3">马主</th><th className="px-4 py-3" /></tr></thead>
            <tbody className="divide-y divide-stone-800 bg-stone-950/50">
              {(profiles ?? []).map((profile) => (
                <tr key={profile.id}>
                  <td className="px-4 py-3 text-amber-200">{profile.role === "PLAYER" ? "玩家" : "GM"}</td>
                  <td className="px-4 py-3">{profile.display_name ?? "—"}</td>
                  <td className="px-4 py-3 text-stone-400">{emailsByUserId.get(profile.id) ?? "—"}</td>
                  <td className="px-4 py-3 text-stone-400">{profile.owner_id ? ownerNames.get(profile.owner_id) ?? "已绑定" : "—"}</td>
                  <td className="px-4 py-3 text-right">
                    {profile.role === "PLAYER" && (
                      <Link className="text-amber-200 hover:text-amber-100" href={`/admin/users/${profile.id}`}>
                        查看 / 编辑
                      </Link>
                    )}
                  </td>
                </tr>
              ))}
              {!profiles?.length && <tr><td className="px-4 py-8 text-stone-500" colSpan={5}>尚无用户资料。</td></tr>}
            </tbody>
          </table>
        </div>
      </section>
      <section className="h-fit rounded-xl border border-stone-800 bg-stone-900 p-5">
        <h2 className="font-semibold text-amber-200">创建玩家账号</h2>
        <form action={createPlayer} className="mt-5 space-y-4">
          <label className="admin-label" htmlFor="owner_id">绑定空闲马主
            <select className="admin-input" disabled={!availableOwners.length} id="owner_id" name="owner_id" required>
              <option value="">选择马主</option>
              {availableOwners.map((owner) => <option key={owner.id} value={owner.id}>{owner.display_name}</option>)}
            </select>
          </label>
          <label className="admin-label" htmlFor="display_name">显示名（可选）<input className="admin-input" id="display_name" name="display_name" /></label>
          <label className="admin-label" htmlFor="email">邮箱<input autoComplete="off" className="admin-input" id="email" name="email" required type="email" /></label>
          <label className="admin-label" htmlFor="password">初始密码<input autoComplete="new-password" className="admin-input" id="password" minLength={8} name="password" required type="text" /></label>
          {!availableOwners.length && <p className="text-sm text-stone-500">没有空闲马主；请先创建马主，或检查已有绑定。</p>}
          <button className="admin-button w-full" disabled={!availableOwners.length}>创建玩家账号</button>
        </form>
      </section>
    </main>
  );
}
