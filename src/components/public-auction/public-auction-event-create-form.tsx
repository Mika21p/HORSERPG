"use client";

import { useRef, useState } from "react";
import { useRouter } from "next/navigation";

import { parseAuctionAmount } from "@/lib/public-auction/ui";
import { createClient } from "@/lib/supabase/client";

export function PublicAuctionEventCreateForm() {
  const router = useRouter();
  const clientRef = useRef<ReturnType<typeof createClient> | null>(null);
  const [wpYear, setWpYear] = useState("");
  const [name, setName] = useState("");
  const [minimumIncrement, setMinimumIncrement] = useState("100000");
  const [notice, setNotice] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);
  const [awaitingConfirmation, setAwaitingConfirmation] = useState(false);

  function beginSubmit() {
    const increment = parseAuctionAmount(minimumIncrement);
    const year = Number(wpYear);
    if (!Number.isInteger(year) || year < 1 || !name.trim() || increment === null || increment < BigInt(100_000) || increment % BigInt(100_000) !== BigInt(0)) {
      setNotice("请填写正整数 WP 年份、名称，以及至少 10 万且为 10 万整数倍的最小加价。\n");
      return;
    }
    setAwaitingConfirmation(true);
  }

  async function submit() {
    const increment = parseAuctionAmount(minimumIncrement);
    const year = Number(wpYear);
    if (increment === null) return;
    setSaving(true);
    if (!clientRef.current) clientRef.current = createClient();
    const { error } = await clientRef.current.rpc("create_public_auction_event", { p_wp_year: year, p_name: name.trim(), p_minimum_increment: increment.toString() });
    setSaving(false);
    if (error) {
      setNotice("Event 未创建。每个 WP 年份只能有一届公开拍卖，且只有 GM 可以创建。");
      return;
    }
    setNotice("公开拍卖 Event 已创建为草稿。");
    setName("");
    setAwaitingConfirmation(false);
    router.refresh();
  }

  return <section className="rounded-xl border border-stone-800 bg-stone-900 p-6"><h2 className="text-xl font-semibold text-amber-200">创建 Event</h2><div className="mt-5 grid gap-3 lg:grid-cols-[8rem_minmax(0,1fr)_10rem_auto]"><input className="admin-input mt-0" min="1" onChange={(input) => setWpYear(input.target.value)} placeholder="WP 年份" type="number" value={wpYear} /><input className="admin-input mt-0" onChange={(input) => setName(input.target.value)} placeholder="Event 名称" value={name} /><input className="admin-input mt-0" onChange={(input) => setMinimumIncrement(input.target.value)} placeholder="最小加价" value={minimumIncrement} /><button className="admin-button" disabled={saving} onClick={beginSubmit} type="button">创建 Event</button></div>{awaitingConfirmation && <div className="mt-4 rounded-lg border border-amber-300/40 bg-amber-300/5 p-4 text-sm text-amber-100"><p>确认创建新的公开拍卖 Event？</p><div className="mt-3 flex gap-2"><button className="rounded-lg border border-stone-600 px-3 py-2 text-stone-100" onClick={() => setAwaitingConfirmation(false)} type="button">取消</button><button className="admin-button" disabled={saving} onClick={() => void submit()} type="button">{saving ? "正在创建…" : "确认创建"}</button></div></div>}{notice && <p aria-live="polite" className="mt-3 text-sm text-amber-100">{notice}</p>}</section>;
}
