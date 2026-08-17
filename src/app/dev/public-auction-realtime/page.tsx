import { notFound } from "next/navigation";

import { PublicAuctionRealtimeHarness } from "@/components/public-auction-realtime-harness";
import { AppShell } from "@/components/app-shell";
import { requireUser } from "@/lib/auth/session";

export const dynamic = "force-dynamic";

type PageProps = {
  searchParams: Promise<{ eventId?: string }>;
};

/** This development harness is intentionally absent from production routes. */
export default async function PublicAuctionRealtimeHarnessPage({ searchParams }: PageProps) {
  if (process.env.NODE_ENV !== "development") {
    notFound();
  }

  const [{ eventId }, { user, profile }] = await Promise.all([searchParams, requireUser()]);

  return (
    <AppShell email={user.email} isGM={profile?.role === "GM"}>
      <main className="mx-auto w-full max-w-6xl px-6 py-10">
        <p className="text-sm font-semibold tracking-[0.18em] text-amber-300">DEVELOPMENT ONLY · PUBLIC AUCTION</p>
        <h1 className="mt-3 text-3xl font-semibold">Realtime Snapshot Harness</h1>
        <p className="mt-3 max-w-3xl text-stone-400">用于本地多客户端验证，不是正式拍卖 UI。生产环境会返回 404。</p>
        <PublicAuctionRealtimeHarness initialEventId={eventId ?? ""} />
      </main>
    </AppShell>
  );
}
