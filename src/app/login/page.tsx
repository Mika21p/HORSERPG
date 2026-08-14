import { redirect } from "next/navigation";

import { LoginForm } from "@/app/login/login-form";
import { getCurrentSession } from "@/lib/auth/session";

export default async function LoginPage() {
  const { user, profile } = await getCurrentSession();

  if (user) {
    redirect(profile?.role === "GM" ? "/admin" : "/");
  }

  return (
    <main className="flex min-h-screen items-center justify-center bg-stone-950 px-6 text-stone-100">
      <section className="w-full max-w-md rounded-2xl border border-amber-200/20 bg-stone-900 p-8 shadow-2xl shadow-black/20">
        <p className="text-sm font-semibold tracking-[0.24em] text-amber-300">HORSE RPG</p>
        <h1 className="mt-4 text-3xl font-semibold tracking-tight">登录</h1>
        <p className="mt-3 text-sm leading-6 text-stone-400">
          第一版账号由 GM 创建。请使用分配给你的邮箱和密码登录。
        </p>
        <LoginForm />
      </section>
    </main>
  );
}
