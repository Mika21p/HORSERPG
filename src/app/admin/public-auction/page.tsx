import Link from "next/link";

import { PublicAuctionEventCreateForm } from "@/components/public-auction/public-auction-event-create-form";
import { formatPublicAuctionStatus } from "@/lib/public-auction/ui";
import { requireGM } from "@/lib/auth/session";

export const dynamic = "force-dynamic";

export default async function AdminPublicAuctionIndexPage() {
  const { supabase } = await requireGM();
  const [{ data: events }, { data: lots }] = await Promise.all([
    supabase.from("public_auction_events").select("id, name, wp_year, status, minimum_increment").order("wp_year", { ascending: false }),
    supabase.from("public_auction_lots").select("event_id, id, status, lot_number").order("lot_number"),
  ]);
  const lotsByEvent = new Map<string, { total: number; finished: number; current: number | null }>();
  for (const lot of lots ?? []) {
    const current = lotsByEvent.get(lot.event_id) ?? { total: 0, finished: 0, current: null };
    current.total += 1;
    if (["SOLD", "PASSED"].includes(lot.status)) current.finished += 1;
    if (!["SOLD", "PASSED", "QUEUED"].includes(lot.status)) current.current = lot.lot_number;
    lotsByEvent.set(lot.event_id, current);
  }

  return <main className="mx-auto w-full max-w-6xl px-6 py-10">
    <p className="text-sm font-semibold tracking-[0.24em] text-amber-300">GM · PUBLIC AUCTION</p>
    <h1 className="mt-3 text-3xl font-semibold tracking-tight">年末公开拍卖管理</h1>
    <p className="mt-3 text-sm leading-6 text-stone-400">先在草稿中加入标的，再由 GM 明确开放拍卖、展示资料和开始每一轮竞价。</p>
    <div className="mt-8"><PublicAuctionEventCreateForm /></div>
    <section className="mt-8 grid gap-4">{(events ?? []).map((event) => { const details = lotsByEvent.get(event.id) ?? { total: 0, finished: 0, current: null }; return <article className="flex flex-col gap-4 rounded-xl border border-stone-800 bg-stone-900 p-6 sm:flex-row sm:items-center sm:justify-between" key={event.id}><div><p className="font-mono text-sm font-semibold text-amber-300">WP {event.wp_year}</p><h2 className="mt-2 text-xl font-semibold">{event.name}</h2><p className="mt-2 text-sm text-stone-400">{formatPublicAuctionStatus(event.status)} · 标的：{details.total} · 已完成：{details.finished} · 当前：{details.current ? `标的 ${String(details.current).padStart(3, "0")}` : "—"}</p></div><Link className="admin-button" href={`/admin/public-auction/${event.id}`}>进入主持台</Link></article>; })}{!events?.length && <p className="rounded-xl border border-stone-800 bg-stone-900 p-6 text-stone-500">还没有公开拍卖届次。</p>}</section>
  </main>;
}
