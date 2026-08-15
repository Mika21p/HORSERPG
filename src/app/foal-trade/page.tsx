import Link from "next/link";

import { AppShell } from "@/components/app-shell";
import { formatDateTime, formatFoalTradeSessionStatus } from "@/lib/format";
import { requireUser } from "@/lib/auth/session";

export const dynamic = "force-dynamic";

export default async function FoalTradeLobbyPage() {
  const { supabase, user, profile } = await requireUser();
  let query = supabase
    .from("foal_trade_sessions")
    .select("id, wp_year, starts_at, ends_at, status")
    .order("wp_year", { ascending: false });

  // Draft sessions are GM working data in the application UI. The database
  // remains the authorization source, and the GM may still view all sessions.
  if (profile?.role !== "GM") {
    query = query.neq("status", "DRAFT");
  }

  const { data: sessions } = await query;
  const openSession = (sessions ?? []).find((session) => session.status === "OPEN");

  return (
    <AppShell email={user.email} isGM={profile?.role === "GM"}>
      <main className="mx-auto w-full max-w-6xl px-6 py-10">
        <section className="flex flex-col justify-between gap-5 sm:flex-row sm:items-end">
          <div>
            <p className="text-sm font-semibold tracking-[0.18em] text-amber-300">AUGUST FOAL TRADE</p>
            <h1 className="mt-3 text-3xl font-semibold tracking-tight">庭先取引</h1>
            <p className="mt-3 max-w-2xl text-stone-400">查看每届公开 Lot、最低报价与已经确认的最终成交结果。秘密报价与 GM 询问内容仅显示给其所属 PLAYER。</p>
          </div>
          {openSession && (
            <Link className="admin-button" href={`/foal-trade/${openSession.id}`}>
              进入当前开放届次（WP {openSession.wp_year}）
            </Link>
          )}
        </section>

        <section className="mt-8 grid gap-4 md:grid-cols-2">
          {(sessions ?? []).map((session) => (
            <Link
              className={`rounded-xl border p-6 transition hover:border-amber-300/60 ${
                session.status === "OPEN"
                  ? "border-amber-300/60 bg-amber-300/10"
                  : "border-stone-800 bg-stone-900 hover:bg-stone-800"
              }`}
              href={`/foal-trade/${session.id}`}
              key={session.id}
            >
              <div className="flex items-start justify-between gap-4">
                <div>
                  <p className="text-sm font-semibold text-amber-200">WP {session.wp_year} 年庭先取引</p>
                  <p className="mt-2 text-sm text-stone-400">状态：{formatFoalTradeSessionStatus(session.status)}</p>
                </div>
                {session.status === "OPEN" && <span className="rounded-full bg-amber-300 px-3 py-1 text-xs font-bold text-stone-950">OPEN</span>}
              </div>
              <dl className="mt-6 grid gap-3 text-sm sm:grid-cols-2">
                <div><dt className="text-stone-500">现实开始时间（中国标准时间）</dt><dd className="mt-1 text-stone-200">{formatDateTime(session.starts_at)}</dd></div>
                <div><dt className="text-stone-500">现实截止时间（中国标准时间）</dt><dd className="mt-1 text-stone-200">{formatDateTime(session.ends_at)}</dd></div>
              </dl>
            </Link>
          ))}
          {!sessions?.length && <p className="text-stone-500">目前没有可浏览的庭先届次。</p>}
        </section>
      </main>
    </AppShell>
  );
}
