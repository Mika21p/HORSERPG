"use client";

import { useState } from "react";

import { usePublicAuctionRealtime } from "@/lib/public-auction/use-public-auction-realtime";

type PublicAuctionRealtimeHarnessProps = {
  initialEventId: string;
};

/** Development-only, intentionally plain Realtime state verification aid. */
export function PublicAuctionRealtimeHarness({ initialEventId }: PublicAuctionRealtimeHarnessProps) {
  const [inputEventId, setInputEventId] = useState(initialEventId);
  const [eventId, setEventId] = useState(initialEventId || null);

  return (
    <section className="mt-6 rounded-xl border border-stone-800 bg-stone-900 p-6">
      <h2 className="text-xl font-semibold text-amber-200">Realtime 状态验证</h2>
      <p className="mt-2 text-sm leading-6 text-stone-400">
        Broadcast 只会触发重新读取权威 Snapshot；这里不会把消息 Payload 当成拍卖状态。
      </p>

      <form
        className="mt-5 flex flex-col gap-3 sm:flex-row"
        onSubmit={(event) => {
          event.preventDefault();
          setEventId(inputEventId.trim() || null);
        }}
      >
        <input
          aria-label="公开拍卖 Event ID"
          className="admin-input mt-0 flex-1"
          onChange={(event) => setInputEventId(event.target.value)}
          placeholder="Public Auction Event UUID"
          value={inputEventId}
        />
        <button className="admin-button" type="submit">开始监听</button>
      </form>

      <RealtimeStatus eventId={eventId} key={eventId ?? "no-event"} />
    </section>
  );
}

function RealtimeStatus({ eventId }: { eventId: string | null }) {
  const realtime = usePublicAuctionRealtime(eventId);

  return (
    <>
      <dl className="mt-6 grid gap-4 text-sm sm:grid-cols-2 lg:grid-cols-4">
        <div><dt className="text-stone-500">连接状态</dt><dd className="mt-1 font-medium text-stone-100">{realtime.connectionState}</dd></div>
        <div><dt className="text-stone-500">收到通知</dt><dd className="mt-1 font-mono text-stone-100">{realtime.broadcastCount}</dd></div>
        <div><dt className="text-stone-500">Snapshot 刷新</dt><dd className="mt-1 font-mono text-stone-100">{realtime.snapshotRefreshCount}</dd></div>
        <div><dt className="text-stone-500">刷新中</dt><dd className="mt-1 text-stone-100">{realtime.isRefreshing ? "是" : "否"}</dd></div>
      </dl>

      {realtime.snapshotError && <p className="mt-4 text-sm text-red-200">{realtime.snapshotError}</p>}

      <pre className="mt-6 max-h-[34rem] overflow-auto rounded-lg border border-stone-800 bg-stone-950 p-4 text-xs leading-6 text-stone-300">
        {realtime.snapshot ? JSON.stringify(realtime.snapshot, null, 2) : "尚未取得 Snapshot。"}
      </pre>
    </>
  );
}
