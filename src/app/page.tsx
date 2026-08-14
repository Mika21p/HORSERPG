import { AppShell } from "@/components/app-shell";
import { requireUser } from "@/lib/auth/session";

export const dynamic = "force-dynamic";

export default async function Home() {
  const { supabase, user, profile } = await requireUser();
  const { data: gameState } = await supabase
    .from("game_state")
    .select("current_wp_year, current_wp_month, current_wp_week")
    .maybeSingle();

  return (
    <AppShell email={user.email} isGM={profile?.role === "GM"}>
      <main className="mx-auto w-full max-w-6xl px-6 py-12">
        <section className="rounded-2xl border border-amber-200/20 bg-stone-900 p-8 shadow-2xl shadow-black/20 sm:p-12">
          <p className="text-sm font-semibold tracking-[0.24em] text-amber-300">HORSE RPG</p>
          <h1 className="mt-4 text-4xl font-semibold tracking-tight">HorseRPG</h1>
          <p className="mt-5 max-w-2xl leading-7 text-stone-300">
            已登录。你可以查看公开的 Owner 与 Horse 资料；GM 另可进入管理后台维护 Core 数据。
          </p>
          <div className="mt-8 rounded-xl border border-stone-800 bg-stone-950/70 p-5">
            <p className="text-sm font-medium text-stone-400">当前 Winning Post 时间</p>
            <p className="mt-2 text-xl font-semibold text-stone-100">
              {gameState
                ? `${gameState.current_wp_year}年 ${String(gameState.current_wp_month).padStart(2, "0")}月 第${gameState.current_wp_week}周`
                : "当前游戏时间尚未由 GM 设置"}
            </p>
          </div>
        </section>
      </main>
    </AppShell>
  );
}
