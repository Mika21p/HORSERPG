"use client";

import { useCallback, useEffect, useRef, useState } from "react";

import type { PublicAuctionSnapshot } from "@/lib/public-auction/types";
import { createClient } from "@/lib/supabase/client";

export type PublicAuctionRealtimeConnectionState =
  | "idle"
  | "connecting"
  | "connected"
  | "reconnecting"
  | "disconnected"
  | "error";

type SnapshotResponse = PublicAuctionSnapshot | { error: string };
type InFlightSnapshot = {
  eventId: string;
  requestId: number;
  controller: AbortController;
};

const REFRESH_DEBOUNCE_MS = 100;
const MAX_RECONNECT_DELAY_MS = 8_000;

/**
 * Subscribes to one private Event Channel. Broadcast payloads are invalidation
 * signals only; state always comes from the atomic RLS-protected snapshot.
 */
export function usePublicAuctionRealtime(eventId: string | null) {
  const [snapshot, setSnapshot] = useState<PublicAuctionSnapshot | null>(null);
  const [snapshotEventId, setSnapshotEventId] = useState<string | null>(eventId);
  const [connectionState, setConnectionState] = useState<PublicAuctionRealtimeConnectionState>("idle");
  const [snapshotError, setSnapshotError] = useState<string | null>(null);
  const [snapshotErrorEventId, setSnapshotErrorEventId] = useState<string | null>(eventId);
  const [isRefreshing, setIsRefreshing] = useState(false);
  const [broadcastCount, setBroadcastCount] = useState(0);
  const [snapshotRefreshCount, setSnapshotRefreshCount] = useState(0);

  const activeEventIdRef = useRef(eventId);
  const isMountedRef = useRef(true);
  const requestSequenceRef = useRef(0);
  const refreshTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const inFlightSnapshotRef = useRef<InFlightSnapshot | null>(null);
  const queuedRefreshEventIdRef = useRef<string | null>(null);
  const refreshSnapshotRef = useRef<(() => Promise<void>) | null>(null);

  async function refreshSnapshot() {
    const activeEventId = activeEventIdRef.current;
    if (!activeEventId) {
      return;
    }

    const running = inFlightSnapshotRef.current;
    if (running?.eventId === activeEventId) {
      queuedRefreshEventIdRef.current = activeEventId;
      return;
    }

    const request: InFlightSnapshot = {
      eventId: activeEventId,
      requestId: requestSequenceRef.current + 1,
      controller: new AbortController(),
    };
    requestSequenceRef.current = request.requestId;
    inFlightSnapshotRef.current = request;

    if (isMountedRef.current) {
      setIsRefreshing(true);
    }

    try {
      const response = await fetch(
        `/api/public-auction/events/${encodeURIComponent(activeEventId)}/snapshot`,
        {
          cache: "no-store",
          credentials: "same-origin",
          signal: request.controller.signal,
        },
      );
      const body = (await response.json()) as SnapshotResponse;

      if (!response.ok || "error" in body) {
        throw new Error("error" in body ? body.error : "Auction snapshot is unavailable.");
      }

      if (isMountedRef.current && activeEventIdRef.current === activeEventId) {
        setSnapshotEventId(activeEventId);
        setSnapshot(body);
        setSnapshotErrorEventId(activeEventId);
        setSnapshotError(null);
        setSnapshotRefreshCount((count) => count + 1);
      }
    } catch (error) {
      if (
        !(error instanceof DOMException && error.name === "AbortError")
        && isMountedRef.current
        && activeEventIdRef.current === activeEventId
      ) {
        setSnapshotErrorEventId(activeEventId);
        setSnapshotError("权威拍卖状态暂时无法刷新；恢复连接后会再次同步。");
      }
    } finally {
      if (inFlightSnapshotRef.current === request) {
        inFlightSnapshotRef.current = null;
        if (isMountedRef.current && activeEventIdRef.current === activeEventId) {
          setIsRefreshing(false);
        }

        if (queuedRefreshEventIdRef.current === activeEventId) {
          queuedRefreshEventIdRef.current = null;
          void refreshSnapshotRef.current?.();
        }
      }
    }
  }

  useEffect(() => {
    refreshSnapshotRef.current = refreshSnapshot;
  });

  const queueSnapshotRefresh = useCallback(() => {
    if (!activeEventIdRef.current || refreshTimerRef.current) {
      return;
    }

    refreshTimerRef.current = setTimeout(() => {
      refreshTimerRef.current = null;
      void refreshSnapshotRef.current?.();
    }, REFRESH_DEBOUNCE_MS);
  }, []);

  // Snapshot-first: a private Realtime channel is an optimization, never a
  // prerequisite for the first authoritative state read.
  useEffect(() => {
    activeEventIdRef.current = eventId;
    const previousRequest = inFlightSnapshotRef.current;
    if (previousRequest && previousRequest.eventId !== eventId) {
      previousRequest.controller.abort();
    }
    if (refreshTimerRef.current) {
      clearTimeout(refreshTimerRef.current);
      refreshTimerRef.current = null;
    }
    queuedRefreshEventIdRef.current = null;

    queueMicrotask(() => {
      if (!isMountedRef.current || activeEventIdRef.current !== eventId) {
        return;
      }

      setSnapshotEventId(eventId);
      setSnapshot(null);
      setSnapshotErrorEventId(eventId);
      setSnapshotError(null);
      setIsRefreshing(false);
      setBroadcastCount(0);
      setSnapshotRefreshCount(0);

      if (!eventId) {
        setConnectionState("idle");
        return;
      }

      setConnectionState("connecting");
      void refreshSnapshotRef.current?.();
    });
  }, [eventId]);

  useEffect(() => {
    isMountedRef.current = true;
    return () => {
      isMountedRef.current = false;
      inFlightSnapshotRef.current?.controller.abort();
      if (refreshTimerRef.current) {
        clearTimeout(refreshTimerRef.current);
        refreshTimerRef.current = null;
      }
    };
  }, []);

  useEffect(() => {
    if (!eventId) {
      return;
    }

    const supabase = createClient();
    let disposed = false;
    let channel: ReturnType<typeof supabase.channel> | null = null;
    let reconnectTimer: ReturnType<typeof setTimeout> | null = null;
    let reconnectAttempt = 0;

    const clearReconnectTimer = () => {
      if (reconnectTimer) {
        clearTimeout(reconnectTimer);
        reconnectTimer = null;
      }
    };

    const removeCurrentChannel = async (candidate?: ReturnType<typeof supabase.channel>) => {
      const channelToRemove = candidate ?? channel;
      if (!channelToRemove) {
        return;
      }
      if (channel === channelToRemove) {
        channel = null;
      }
      await supabase.removeChannel(channelToRemove);
    };

    const scheduleReconnect = () => {
      if (disposed || reconnectTimer || channel) {
        return;
      }

      setConnectionState("reconnecting");
      const delay = Math.min(1_000 * 2 ** reconnectAttempt, MAX_RECONNECT_DELAY_MS);
      reconnectAttempt += 1;
      reconnectTimer = setTimeout(() => {
        reconnectTimer = null;
        void subscribe(true);
      }, delay);
    };

    const onBroadcast = () => {
      if (disposed) {
        return;
      }
      setBroadcastCount((count) => count + 1);
      queueSnapshotRefresh();
    };

    const subscribe = async (isReconnect = false) => {
      if (disposed || channel) {
        return;
      }

      try {
        setConnectionState(isReconnect ? "reconnecting" : "connecting");
        await supabase.realtime.setAuth();
        if (disposed || channel) {
          return;
        }

        const nextChannel = supabase
          .channel(`public-auction:${eventId}`, { config: { private: true } })
          .on("broadcast", { event: "auction_state_changed" }, onBroadcast)
          .subscribe((status) => {
            if (disposed || channel !== nextChannel) {
              return;
            }

            if (status === "SUBSCRIBED") {
              reconnectAttempt = 0;
              setConnectionState("connected");
              // A state change can race the WebSocket join, so always reread.
              queueSnapshotRefresh();
            } else if (status === "CHANNEL_ERROR" || status === "TIMED_OUT") {
              // The client library owns normal rejoin behavior for these.
              setConnectionState("reconnecting");
            } else if (status === "CLOSED") {
              // CLOSED does not recreate a Channel. Remove this instance, then
              // make exactly one bounded-backoff re-subscribe attempt.
              void (async () => {
                await removeCurrentChannel(nextChannel);
                scheduleReconnect();
              })();
            }
          });
        channel = nextChannel;
      } catch {
        if (!disposed) {
          scheduleReconnect();
        }
      }
    };

    void subscribe();

    const onOnline = () => {
      if (!disposed) {
        setConnectionState((current) => (current === "connected" ? current : "reconnecting"));
        queueSnapshotRefresh();
        scheduleReconnect();
      }
    };
    const onVisibilityChange = () => {
      if (!disposed && document.visibilityState === "visible") {
        queueSnapshotRefresh();
      }
    };

    window.addEventListener("online", onOnline);
    document.addEventListener("visibilitychange", onVisibilityChange);

    return () => {
      disposed = true;
      clearReconnectTimer();
      window.removeEventListener("online", onOnline);
      document.removeEventListener("visibilitychange", onVisibilityChange);
      void removeCurrentChannel();
    };
  }, [eventId, queueSnapshotRefresh]);

  return {
    snapshot: snapshotEventId === eventId ? snapshot : null,
    connectionState,
    snapshotError: snapshotErrorEventId === eventId ? snapshotError : null,
    isRefreshing,
    broadcastCount,
    snapshotRefreshCount,
    refreshSnapshot: queueSnapshotRefresh,
  };
}
