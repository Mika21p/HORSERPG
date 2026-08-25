"use client";

import { FormEvent, useRef, useState } from "react";
import { useRouter } from "next/navigation";

import { recordPostRaceHealth, type InjuryFacts } from "@/app/admin/horses/health-actions";

type PostRaceHealthFormProps = {
  actualRaceId: string;
  horseId: string;
  raceResultId: string;
  currentStamina: number | null;
  defaultWp: { year: number; month: number; week: number };
  isProcessed: boolean;
  hasLaterActiveHealthEvent: boolean;
};

function injuryFacts(formData: FormData): InjuryFacts | null | undefined {
  if (String(formData.get("injury_enabled") ?? "") !== "on") return null;
  const values = ["start_year", "start_month", "start_week", "end_year", "end_month", "end_week"].map((name) => String(formData.get(`injury_${name}`) ?? ""));
  if (!values.every((value) => /^\d+$/.test(value))) return undefined;
  const [startYear, startMonth, startWeek, endYear, endMonth, endWeek] = values.map(Number);
  return { startYear, startMonth, startWeek, endYear, endMonth, endWeek, notes: String(formData.get("injury_notes") ?? "") };
}

function WpInput({ label, name, defaultValue, max }: { label: string; name: string; defaultValue: number; max?: number }) {
  return <label className="admin-label">{label}<input className="admin-input" defaultValue={defaultValue} min="1" max={max} name={name} required step="1" type="number" /></label>;
}

export function PostRaceHealthForm({ actualRaceId, horseId, raceResultId, currentStamina, defaultWp, isProcessed, hasLaterActiveHealthEvent }: PostRaceHealthFormProps) {
  const router = useRouter();
  const requestId = useRef(crypto.randomUUID());
  const [hasInjury, setHasInjury] = useState(false);
  const [feedback, setFeedback] = useState<{ ok: boolean; message: string } | null>(null);
  const [busy, setBusy] = useState(false);

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const formData = new FormData(event.currentTarget);
    const staminaText = String(formData.get("stamina_after") ?? "").trim();
    const staminaAfter = currentStamina === null ? null : /^\d+$/.test(staminaText) ? Number(staminaText) : undefined;
    const injury = injuryFacts(formData);
    if (staminaAfter === undefined || injury === undefined || (staminaAfter !== null && (staminaAfter < 0 || staminaAfter > 100))) {
      setFeedback({ ok: false, message: "请填写 0–100 的整数赛后体力，以及完整伤病时间。" });
      return;
    }
    setBusy(true);
    const result = await recordPostRaceHealth({
      horseId,
      actualRaceId,
      raceResultId,
      staminaAfter,
      notes: String(formData.get("notes") ?? ""),
      requestId: requestId.current,
      injury,
    });
    setBusy(false);
    setFeedback(result);
    if (result.ok) {
      requestId.current = crypto.randomUUID();
      router.refresh();
    }
  }

  if (isProcessed) return <div className="mt-4 rounded-lg border border-emerald-400/35 bg-emerald-400/5 p-4 text-sm leading-6 text-emerald-100"><p className="font-semibold">赛后状态：已处理</p><p className="mt-1 text-emerald-100/80">该有效赛果已有 有效赛后健康事件。需要纠错或作废时，请到 马匹详情的健康历史执行受控操作。</p></div>;

  return <div className="mt-5"><p className="w-fit rounded-full border border-amber-300/40 bg-amber-300/5 px-3 py-1 text-xs font-semibold text-amber-100">赛后状态：待处理</p><details className="mt-3 rounded-lg border border-amber-300/25 bg-amber-300/5 p-4"><summary className="cursor-pointer text-sm font-semibold text-amber-100">处理赛后状态</summary><p className="mt-2 text-xs leading-5 text-stone-400">赛后处理是独立的 GM 裁定。{currentStamina === null ? "此马匹 未启用体力管理，将记录为未启用体力的赛后处理；仍可独立记录伤病。" : `当前体力为 ${currentStamina} / 100，必须填写 0–100 的赛后体力。`}</p>{hasLaterActiveHealthEvent && <p className="mt-3 rounded border border-amber-300/30 bg-stone-950/50 p-3 text-xs leading-5 text-amber-100">提示：此马匹 已有更晚的有效健康事件。数据库会维持事件链并拒绝不安全的补录。</p>}<form className="mt-4 space-y-4" onSubmit={submit}>{currentStamina === null ? <input name="stamina_after" type="hidden" value="" /> : <label className="admin-label">赛后体力（0–100）<input className="admin-input" defaultValue={currentStamina} inputMode="numeric" max="100" min="0" name="stamina_after" required type="number" /></label>}<label className="flex items-center gap-2 text-sm text-red-100"><input checked={hasInjury} name="injury_enabled" onChange={(event) => setHasInjury(event.target.checked)} type="checkbox" />同时记录赛后伤病</label>{hasInjury && <div className="space-y-4 rounded-lg border border-red-400/25 bg-red-400/5 p-4"><div><p className="text-xs text-stone-400">伤病开始</p><div className="mt-2 grid gap-3 sm:grid-cols-3"><WpInput defaultValue={defaultWp.year} label="WP 年" name="injury_start_year" /><WpInput defaultValue={defaultWp.month} label="月" max={12} name="injury_start_month" /><WpInput defaultValue={defaultWp.week} label="周" max={5} name="injury_start_week" /></div></div><div><p className="text-xs text-stone-400">伤病结束</p><div className="mt-2 grid gap-3 sm:grid-cols-3"><WpInput defaultValue={defaultWp.year} label="WP 年" name="injury_end_year" /><WpInput defaultValue={defaultWp.month} label="月" max={12} name="injury_end_month" /><WpInput defaultValue={defaultWp.week} label="周" max={5} name="injury_end_week" /></div></div><label className="admin-label">公开伤病说明（可选）<textarea className="admin-input min-h-20" name="injury_notes" placeholder="会显示给已认证玩家，不要填写 GM 私密信息。" /></label></div>}<label className="admin-label">GM 备注（可选）<textarea className="admin-input min-h-20" name="notes" placeholder="仅 GM 可见。" /></label><button className="admin-button" disabled={busy} type="submit">{busy ? "正在保存…" : "确认赛后状态"}</button></form>{feedback && <p aria-live="polite" className={`mt-3 rounded border p-3 text-sm leading-6 ${feedback.ok ? "border-emerald-400/35 bg-emerald-400/5 text-emerald-100" : "border-red-400/35 bg-red-400/5 text-red-100"}`}>{feedback.message}</p>}</details></div>;
}
