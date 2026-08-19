import Link from "next/link";

import { createFoalTradeSession } from "@/app/admin/foal-trade/actions";
import { ActionForm } from "@/components/action-form";
import { Notice } from "@/components/notice";
import { requireGM } from "@/lib/auth/session";
import { formatDateTime, formatFoalTradeSessionStatus } from "@/lib/format";

type PageProps = { searchParams: Promise<{ notice?: string }> };

export const dynamic = "force-dynamic";

export default async function AdminFoalTradePage({ searchParams }: PageProps) {
  const [{ supabase }, { notice }] = await Promise.all([requireGM(), searchParams]);
  const [{ data: sessions }, { data: lots }, { data: settlements }] = await Promise.all([
    supabase
      .from("foal_trade_sessions")
      .select("id, wp_year, starts_at, ends_at, status")
      .order("wp_year", { ascending: false }),
    supabase.from("foal_trade_lots").select("session_id"),
    supabase.from("foal_trade_settlements").select("session_id"),
  ]);
  const lotCountBySession = new Map<string, number>();
  const settlementCountBySession = new Map<string, number>();
  for (const lot of lots ?? []) {
    lotCountBySession.set(lot.session_id, (lotCountBySession.get(lot.session_id) ?? 0) + 1);
  }
  for (const settlement of settlements ?? []) {
    settlementCountBySession.set(settlement.session_id, (settlementCountBySession.get(settlement.session_id) ?? 0) + 1);
  }

  return (
    <main className="mx-auto grid w-full max-w-7xl gap-8 px-6 py-10 xl:grid-cols-[minmax(0,1fr)_25rem]">
      <section>
        <p className="text-sm font-semibold tracking-[0.18em] text-amber-300">GM · AUGUST FOAL TRADE</p>
        <h1 className="mt-3 text-3xl font-semibold tracking-tight">庭先取引管理</h1>
        <p className="mt-3 max-w-2xl text-stone-400">这里的询问、秘密报价和推荐赢家属于 GM 内部信息。PLAYER 不会通过该页面或其网络响应获得这些记录。</p>
        <Notice message={notice} />
        <div className="mt-6 overflow-hidden rounded-xl border border-stone-800">
          <table className="w-full text-left text-sm">
            <thead className="bg-stone-900 text-stone-400">
              <tr><th className="px-4 py-3 font-medium">WP 年份</th><th className="px-4 py-3 font-medium">状态</th><th className="px-4 py-3 font-medium">现实时间（中国标准时间）</th><th className="px-4 py-3 font-medium">Lot / 已结算</th><th className="px-4 py-3" /></tr>
            </thead>
            <tbody className="divide-y divide-stone-800 bg-stone-950/50">
              {(sessions ?? []).map((session) => (
                <tr key={session.id}>
                  <td className="px-4 py-4 font-semibold text-amber-200">WP {session.wp_year}</td>
                  <td className="px-4 py-4 text-stone-200">{formatFoalTradeSessionStatus(session.status)}</td>
                  <td className="px-4 py-4 text-stone-400"><span className="block">开始：{formatDateTime(session.starts_at)}</span><span className="mt-1 block">截止：{formatDateTime(session.ends_at)}</span></td>
                  <td className="px-4 py-4 font-mono text-stone-300">{lotCountBySession.get(session.id) ?? 0} / {settlementCountBySession.get(session.id) ?? 0}</td>
                  <td className="px-4 py-4 text-right"><Link className="text-amber-200 hover:text-amber-100" href={`/admin/foal-trade/${session.id}`}>管理届次</Link></td>
                </tr>
              ))}
              {!sessions?.length && <tr><td className="px-4 py-8 text-stone-500" colSpan={5}>尚未创建庭先届次。</td></tr>}
            </tbody>
          </table>
        </div>
      </section>

      <section className="h-fit rounded-xl border border-stone-800 bg-stone-900 p-6">
        <h2 className="text-xl font-semibold text-amber-200">创建庭先届次</h2>
        <p className="mt-2 text-sm leading-6 text-stone-400">新届次先以草稿创建。按中国标准时间选择开始日期、时刻与报价时长；系统自动保存真实开始和截止时间。</p>
        <ActionForm action={createFoalTradeSession} className="mt-5 space-y-4" pendingLabel="正在创建…" submitLabel="创建草稿届次">
          <label className="admin-label">WP 年份<input className="admin-input" min="1" name="wp_year" required step="1" type="number" /></label>
          <label className="admin-label">开始日期（中国标准时间）<input className="admin-input" name="start_date" required type="date" /></label>
          <label className="admin-label">开始时刻（中国标准时间）<select className="admin-input" defaultValue="" name="start_time" required><option disabled value="">选择时刻</option><option value="09:00">09:00</option><option value="12:00">12:00</option><option value="18:00">18:00</option><option value="20:00">20:00</option><option value="21:00">21:00</option><option value="22:00">22:00</option></select></label>
          <label className="admin-label">报价时长<select className="admin-input" defaultValue="" name="duration_hours" required><option disabled value="">选择时长</option><option value="1">1 小时</option><option value="3">3 小时</option><option value="6">6 小时</option><option value="12">12 小时</option><option value="24">1 天</option><option value="72">3 天</option><option value="168">7 天</option></select></label>
        </ActionForm>
      </section>
    </main>
  );
}
