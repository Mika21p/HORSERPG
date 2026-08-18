import { notFound } from "next/navigation";

import { AppShell } from "@/components/app-shell";
import { PublicAuctionRoom } from "@/components/public-auction/public-auction-room";
import { requireUser } from "@/lib/auth/session";

export const dynamic = "force-dynamic";

type PageProps = { params: Promise<{ eventId: string }> };

export default async function PublicAuctionEventPage({ params }: PageProps) {
  const [{ eventId }, { profile, supabase, user }] = await Promise.all([params, requireUser()]);
  const { data: event } = await supabase.from("public_auction_events").select("id").eq("id", eventId).maybeSingle();
  if (!event) {
    notFound();
  }

  return <AppShell email={user.email} isGM={profile?.role === "GM"}><PublicAuctionRoom eventId={eventId} viewerOwnerId={profile?.owner_id ?? null} viewerRole={profile?.role ?? null} /></AppShell>;
}
