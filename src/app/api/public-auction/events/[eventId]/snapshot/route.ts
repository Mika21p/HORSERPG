import { getCurrentSession } from "@/lib/auth/session";
import {
  getPublicAuctionSnapshot,
  PublicAuctionSnapshotError,
} from "@/lib/public-auction/snapshot";

export const dynamic = "force-dynamic";

type RouteProps = {
  params: Promise<{ eventId: string }>;
};

/**
 * Returns only the caller's RLS-safe auction snapshot. Realtime broadcasts
 * merely invalidate this resource; they are never treated as business facts.
 */
export async function GET(_request: Request, { params }: RouteProps) {
  const [{ eventId }, session] = await Promise.all([params, getCurrentSession()]);

  if (!session.user) {
    return Response.json({ error: "Authentication is required." }, { status: 401 });
  }

  try {
    const snapshot = await getPublicAuctionSnapshot(session.supabase, eventId);

    if (!snapshot) {
      return Response.json({ error: "Auction event was not found." }, { status: 404 });
    }

    return Response.json(snapshot, {
      headers: { "Cache-Control": "private, no-store" },
    });
  } catch (error) {
    if (error instanceof PublicAuctionSnapshotError) {
      return Response.json({ error: "Auction snapshot is temporarily unavailable." }, { status: 503 });
    }

    return Response.json({ error: "Auction snapshot is temporarily unavailable." }, { status: 500 });
  }
}
