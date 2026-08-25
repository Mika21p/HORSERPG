import Link from "next/link";
import { notFound } from "next/navigation";

import { updatePlayer } from "@/app/admin/actions";
import { Notice } from "@/components/notice";
import { requireGM } from "@/lib/auth/session";
import { createAdminClient } from "@/lib/supabase/admin";

type PageProps = {
  params: Promise<{ id: string }>;
  searchParams: Promise<{ notice?: string }>;
};

export default async function AdminPlayerDetailPage({ params, searchParams }: PageProps) {
  const [{ id }, { notice }, { supabase }] = await Promise.all([params, searchParams, requireGM()]);
  const { data: profile } = await supabase
    .from("user_profiles")
    .select("id, role, owner_id, display_name, created_at")
    .eq("id", id)
    .maybeSingle();

  if (!profile || profile.role !== "PLAYER") {
    notFound();
  }

  const admin = createAdminClient();
  const [{ data: authUser }, { data: owner }] = await Promise.all([
    admin.auth.admin.getUserById(profile.id),
    profile.owner_id
      ? supabase.from("owners").select("display_name").eq("id", profile.owner_id).maybeSingle()
      : Promise.resolve({ data: null }),
  ]);

  if (!authUser.user) {
    notFound();
  }

  return (
    <main className="mx-auto w-full max-w-3xl px-6 py-10">
      <Link className="text-sm text-amber-200 hover:text-amber-100" href="/admin/users">
        ← 用户管理
      </Link>
      <h1 className="mt-5 text-3xl font-semibold tracking-tight">玩家账号管理</h1>
      <Notice message={notice} />
      <section className="mt-6 rounded-xl border border-stone-800 bg-stone-900 p-6">
        <dl className="grid gap-4 text-sm sm:grid-cols-2">
          <div>
            <dt className="text-stone-500">绑定马主</dt>
            <dd className="mt-1 text-stone-100">{owner?.display_name ?? "—"}</dd>
          </div>
          <div>
            <dt className="text-stone-500">创建时间</dt>
            <dd className="mt-1 text-stone-100">{new Date(profile.created_at).toLocaleString("zh-CN")}</dd>
          </div>
        </dl>
        <form action={updatePlayer.bind(null, profile.id)} className="mt-8 max-w-md space-y-4 border-t border-stone-800 pt-6">
          <label className="admin-label" htmlFor="display_name">
            显示名
            <input className="admin-input" defaultValue={profile.display_name ?? ""} id="display_name" name="display_name" />
          </label>
          <label className="admin-label" htmlFor="email">
            登录邮箱
            <input autoComplete="off" className="admin-input" defaultValue={authUser.user.email ?? ""} id="email" name="email" required type="email" />
          </label>
          <label className="admin-label" htmlFor="password">
            新密码（可留空）
            <input autoComplete="new-password" className="admin-input" id="password" minLength={8} name="password" type="text" />
          </label>
          <p className="text-xs leading-5 text-stone-500">旧密码不会回显；填写新密码并保存后将立即覆盖旧密码。新建与重设密码均按 GM 要求直接显示在当前输入框中。</p>
          <button className="admin-button">保存玩家资料</button>
        </form>
      </section>
    </main>
  );
}
