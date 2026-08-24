import { redirect } from "next/navigation";

import { LoginForm } from "@/app/login/login-form";
import { getCurrentSession } from "@/lib/auth/session";

export default async function LoginPage() {
  const { user, profile } = await getCurrentSession();

  if (user) {
    redirect(profile?.role === "GM" ? "/admin" : "/");
  }

  return (
    <main className="grid min-h-screen bg-[#f4f0e7] text-[#202521] lg:grid-cols-[minmax(0,1.08fr)_minmax(28rem,0.92fr)]">
      <section className="relative hidden min-h-screen overflow-hidden bg-[#173f35] p-12 text-white lg:flex lg:flex-col lg:justify-between xl:p-16">
        <div className="absolute -right-40 top-12 h-[34rem] w-[34rem] rounded-full border border-[#d6b66a]/25" />
        <div className="absolute -right-20 top-32 h-[24rem] w-[24rem] rounded-full border border-[#d6b66a]/20" />
        <div className="absolute bottom-20 left-12 h-px w-[60%] bg-gradient-to-r from-[#d6b66a]/70 to-transparent" />
        <div className="relative">
          <p className="text-xs font-bold tracking-[0.32em] text-[#d6b66a]">WINNING POST · CLUB SYSTEM</p>
          <p className="display-title mt-4 text-4xl font-semibold">HorseRPG</p>
        </div>
        <div className="relative max-w-xl pb-10">
          <p className="display-title text-5xl font-semibold leading-[1.15] xl:text-6xl">让每一次报名、竞价与胜利都有迹可循。</p>
          <p className="mt-6 max-w-lg text-base leading-8 text-[#d7ded9]">为 Winning Post 赛马跑团打造的协作会所。连接玩家意图、GM 裁定与完整赛事档案。</p>
          <div className="mt-10 flex items-center gap-4 text-xs font-semibold uppercase tracking-[0.2em] text-[#d6b66a]">
            <span>Stable</span><span className="h-px w-8 bg-current" /><span>Market</span><span className="h-px w-8 bg-current" /><span>Race</span>
          </div>
        </div>
      </section>

      <section className="flex min-h-screen items-center justify-center px-5 py-10 sm:px-10 lg:px-12">
        <div className="w-full max-w-md">
          <div className="mb-10 lg:hidden">
            <p className="text-xs font-bold tracking-[0.28em] text-[#9a7131]">WINNING POST</p>
            <p className="display-title mt-2 text-3xl font-semibold text-[#173f35]">HorseRPG</p>
          </div>
          <div className="rounded-[1.75rem] border border-[#d8d0c2] bg-[#fffcf6] p-7 shadow-[0_24px_70px_rgb(57_47_31/10%)] sm:p-9">
            <p className="text-xs font-bold tracking-[0.2em] text-[#9a7131]">MEMBERS ACCESS</p>
            <h1 className="display-title mt-3 text-4xl font-semibold text-[#173f35]">欢迎归队</h1>
            <p className="mt-3 text-sm leading-7 text-[#68736c]">账号由 GM 统一创建，请使用分配给你的邮箱与密码进入会所。</p>
            <LoginForm />
          </div>
          <p className="mt-6 text-center text-xs text-[#7a837d]">HorseRPG · 赛马跑团管理平台</p>
        </div>
      </section>
    </main>
  );
}
