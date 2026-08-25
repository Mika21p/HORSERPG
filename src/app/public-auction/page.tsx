import Link from "next/link";

import { AppShell } from "@/components/app-shell";
import { formatPublicAuctionStatus } from "@/lib/public-auction/ui";
import { requireUser } from "@/lib/auth/session";

export const dynamic = "force-dynamic";

export default async function PublicAuctionIndexPage() {
  const { profile, supabase, user } = await requireUser();
  const [{ data: events }, { data: revealedLots }] = await Promise.all([
    supabase.from("public_auction_events").select("id, name, wp_year, status").order("wp_year", { ascending: false }),
    supabase.from("public_auction_lots").select("event_id, status").not("revealed_at", "is", null),
  ]);
  const revealedByEvent = new Map<string, string>();
  for (const lot of revealedLots ?? []) {
    if (!["SOLD", "PASSED"].includes(lot.status)) {
      revealedByEvent.set(lot.event_id, lot.status);
    }
  }

  return (
    <AppShell email={user.email} isGM={profile?.role === "GM"}>
      <main className="mx-auto w-full max-w-6xl px-6 py-10">
        <p className="text-sm font-semibold tracking-[0.24em] text-amber-300">公开拍卖</p>
        <h1 className="mt-3 text-3xl font-semibold tracking-tight">年末公开拍卖</h1>
        <p className="mt-3 max-w-2xl text-sm leading-6 text-stone-400">只显示已登录用户可访问的拍卖会。未展示的后续标的不会在拍卖大厅中提前公开。</p>
        <div className="mt-8 grid gap-4">
          {(events ?? []).map((event) => {
            const activeLot = revealedByEvent.get(event.id);
            return <article className="flex flex-col gap-5 rounded-xl border border-stone-800 bg-stone-900 p-6 sm:flex-row sm:items-center sm:justify-between" key={event.id}><div><p className="font-mono text-sm font-semibold text-amber-300">WP {event.wp_year}</p><h2 className="mt-2 text-xl font-semibold text-stone-100">{event.name}</h2><p className="mt-2 text-sm text-stone-400">状态：{formatPublicAuctionStatus(event.status)}{activeLot ? ` · 当前已展示标的：${formatPublicAuctionStatus(activeLot)}` : " · 当前没有已展示标的"}</p></div><Link className="admin-button" href={`/public-auction/${event.id}`}>进入拍卖会</Link></article>;
          })}
          {!events?.length && <p className="rounded-xl border border-stone-800 bg-stone-900 p-6 text-stone-500">目前没有可访问的公开拍卖届次。</p>}
        </div>
      </main>
    </AppShell>
  );
}
