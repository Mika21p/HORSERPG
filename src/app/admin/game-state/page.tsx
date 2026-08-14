import Link from "next/link";

import { saveGameState } from "@/app/admin/actions";
import { Notice } from "@/components/notice";
import { requireGM } from "@/lib/auth/session";

type PageProps = { searchParams: Promise<{ notice?: string }> };

export default async function GameStatePage({ searchParams }: PageProps) {
  const [{ supabase }, { notice }] = await Promise.all([requireGM(), searchParams]);
  const { data: gameState } = await supabase
    .from("game_state")
    .select("current_wp_year, current_wp_month, current_wp_week, updated_at")
    .maybeSingle();

  return (
    <main className="mx-auto w-full max-w-2xl px-6 py-10">
      <Link className="text-sm text-amber-200 hover:text-amber-100" href="/admin">← GM 后台</Link>
      <h1 className="mt-5 text-3xl font-semibold tracking-tight">Game State</h1>
      <p className="mt-3 text-stone-400">此表最多一行；仅 GM 可以创建或更新当前 Winning Post 时间。</p>
      <Notice message={notice} />
      <section className="mt-6 rounded-xl border border-stone-800 bg-stone-900 p-6">
        {gameState ? <p className="mb-6 text-stone-300">当前：{gameState.current_wp_year}年 {gameState.current_wp_month}月 第{gameState.current_wp_week}周</p> : <p className="mb-6 text-stone-500">当前游戏时间尚未由 GM 设置。</p>}
        <form action={saveGameState} className="grid gap-4 sm:grid-cols-3">
          <label className="admin-label" htmlFor="current_wp_year">年<input className="admin-input" defaultValue={gameState?.current_wp_year} id="current_wp_year" min="1" name="current_wp_year" required type="number" /></label>
          <label className="admin-label" htmlFor="current_wp_month">月<input className="admin-input" defaultValue={gameState?.current_wp_month} id="current_wp_month" max="12" min="1" name="current_wp_month" required type="number" /></label>
          <label className="admin-label" htmlFor="current_wp_week">周<input className="admin-input" defaultValue={gameState?.current_wp_week} id="current_wp_week" max="5" min="1" name="current_wp_week" required type="number" /></label>
          <button className="admin-button sm:col-span-3">保存当前时间</button>
        </form>
      </section>
    </main>
  );
}
