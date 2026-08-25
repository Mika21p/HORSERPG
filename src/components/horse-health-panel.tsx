"use client";

import { FormEvent, useRef, useState } from "react";
import { useRouter } from "next/navigation";

import {
  adjustHorseStamina,
  correctLatestHorseHealthEvent,
  createManualInjury,
  resolveHorseInjury,
  voidHorseInjury,
  voidLatestHorseHealthEvent,
  type HealthActionResult,
  type InjuryFacts,
} from "@/app/admin/horses/health-actions";
import { formatHorseHealthEventStatus, formatHorseHealthEventType, formatInjuryStatus, formatWpTime } from "@/lib/format";

export type HealthInjury = {
  id: string;
  status: string;
  startYear: number;
  startMonth: number;
  startWeek: number;
  endYear: number;
  endMonth: number;
  endWeek: number;
  notes: string | null;
  sourceHealthEventId?: string | null;
  resolvedAt?: string | null;
  resolutionReason?: string | null;
  voidedAt?: string | null;
  voidReason?: string | null;
};

export type HorseHealthEvent = {
  id: string;
  eventType: string;
  status: string;
  wpYear: number;
  wpMonth: number;
  wpWeek: number;
  staminaBefore: number | null;
  staminaAfter: number | null;
  notes?: string | null;
  confirmedAt?: string | null;
  voidedAt?: string | null;
  voidReason?: string | null;
  isLatestActive?: boolean;
  sourceInjury?: HealthInjury | null;
};

type HorseHealthPanelProps = {
  horseId: string;
  currentStamina: number | null;
  injuries: HealthInjury[];
  events: HorseHealthEvent[];
  isGM: boolean;
  defaultWp?: { year: number; month: number; week: number } | null;
};

type Feedback = { kind: "success" | "error"; message: string } | null;

function staminaLabel(value: number | null) {
  return value === null ? "未启用" : `${value} / 100`;
}

function eventStaminaLabel(event: HorseHealthEvent) {
  if (event.staminaBefore === null && event.staminaAfter === null && event.eventType === "POST_RACE") return "未启用体力 · 赛后处理完成";
  return `${staminaLabel(event.staminaBefore)} → ${staminaLabel(event.staminaAfter)}`;
}

function parseOptionalStamina(value: string) {
  if (value.trim() === "") return null;
  if (!/^\d+$/.test(value)) return undefined;
  const number = Number(value);
  return number >= 0 && number <= 100 ? number : undefined;
}

function fieldsToInjury(formData: FormData, prefix: string): InjuryFacts | null | undefined {
  const enabled = String(formData.get(`${prefix}_enabled`) ?? "") === "on";
  if (!enabled) return null;
  const values = ["start_year", "start_month", "start_week", "end_year", "end_month", "end_week"].map((name) => String(formData.get(`${prefix}_${name}`) ?? ""));
  if (!values.every((value) => /^\d+$/.test(value))) return undefined;
  const [startYear, startMonth, startWeek, endYear, endMonth, endWeek] = values.map(Number);
  return { startYear, startMonth, startWeek, endYear, endMonth, endWeek, notes: String(formData.get(`${prefix}_notes`) ?? "") };
}

function FeedbackMessage({ feedback }: { feedback: Feedback }) {
  if (!feedback) return null;
  return <p aria-live="polite" className={`mt-3 rounded-lg border p-3 text-sm leading-6 ${feedback.kind === "success" ? "border-emerald-400/35 bg-emerald-400/5 text-emerald-100" : "border-red-400/35 bg-red-400/5 text-red-100"}`}>{feedback.message}</p>;
}

function WpInputs({ prefix, defaultValue }: { prefix: string; defaultValue: { year: number; month: number; week: number } }) {
  return <div className="grid gap-3 sm:grid-cols-3"><label className="admin-label">WP 年<input className="admin-input" defaultValue={defaultValue.year} min="1" name={`${prefix}_year`} required step="1" type="number" /></label><label className="admin-label">月<select className="admin-input" defaultValue={defaultValue.month} name={`${prefix}_month`}>{Array.from({ length: 12 }, (_, index) => index + 1).map((month) => <option key={month} value={month}>{month} 月</option>)}</select></label><label className="admin-label">周<select className="admin-input" defaultValue={defaultValue.week} name={`${prefix}_week`}>{Array.from({ length: 5 }, (_, index) => index + 1).map((week) => <option key={week} value={week}>Week {week}</option>)}</select></label></div>;
}

function InjuryFields({ prefix, injury, defaultWp }: { prefix: string; injury?: HealthInjury | null; defaultWp: { year: number; month: number; week: number } }) {
  const [enabled, setEnabled] = useState(Boolean(injury));
  const start = injury ? { year: injury.startYear, month: injury.startMonth, week: injury.startWeek } : defaultWp;
  const end = injury ? { year: injury.endYear, month: injury.endMonth, week: injury.endWeek } : defaultWp;
  return <fieldset className="rounded-lg border border-red-400/25 bg-red-400/5 p-4"><label className="flex items-center gap-2 text-sm font-medium text-red-100"><input checked={enabled} name={`${prefix}_enabled`} onChange={(event) => setEnabled(event.target.checked)} type="checkbox" />同时记录伤病</label><p className="mt-2 text-xs leading-5 text-stone-400">伤病结束 WP 周按包含处理：从下一 WP 周开始恢复可报名。</p>{enabled && <div className="mt-4 space-y-4"><div><p className="text-xs font-medium text-stone-400">开始时间</p><div className="mt-2"><WpInputs defaultValue={start} prefix={`${prefix}_start`} /></div></div><div><p className="text-xs font-medium text-stone-400">结束时间</p><div className="mt-2"><WpInputs defaultValue={end} prefix={`${prefix}_end`} /></div></div><label className="admin-label">公开伤病说明（可选）<textarea className="admin-input min-h-20" defaultValue={injury?.notes ?? ""} name={`${prefix}_notes`} placeholder="会显示给已认证玩家，不要填写 GM 私密信息。" /></label></div>}</fieldset>;
}

export function HorseHealthPanel({ horseId, currentStamina, injuries, events, isGM, defaultWp }: HorseHealthPanelProps) {
  const router = useRouter();
  const [feedback, setFeedback] = useState<Feedback>(null);
  const staminaRequestId = useRef(crypto.randomUUID());
  const [staminaMode, setStaminaMode] = useState<"set" | "disable">("set");
  const [confirmingDisable, setConfirmingDisable] = useState(false);
  const createInjuryDefault = defaultWp ?? { year: 1, month: 1, week: 1 };

  function finish(result: HealthActionResult, onSuccess?: () => void) {
    setFeedback({ kind: result.ok ? "success" : "error", message: result.message });
    if (result.ok) {
      onSuccess?.();
      router.refresh();
    }
  }

  async function submitStamina(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const formData = new FormData(event.currentTarget);
    const mode = String(formData.get("stamina_mode") ?? "set");
    const staminaAfter = mode === "disable" ? null : parseOptionalStamina(String(formData.get("stamina_after") ?? ""));
    if (staminaAfter === undefined || (mode === "set" && staminaAfter === null)) {
      setFeedback({ kind: "error", message: "请填写 0–100 的整数体力；0 是合法的已启用状态。" });
      return;
    }
    if (currentStamina === staminaAfter) {
      setFeedback({ kind: "error", message: "新的体力与当前体力相同，不会创建无意义的健康事件。" });
      return;
    }
    if (mode === "disable" && !confirmingDisable) {
      setConfirmingDisable(true);
      setFeedback({ kind: "error", message: "请再次确认停止体力管理；已有体力历史不会删除。" });
      return;
    }
    const result = await adjustHorseStamina({ horseId, staminaAfter, reason: String(formData.get("reason") ?? ""), requestId: staminaRequestId.current });
    finish(result, () => { staminaRequestId.current = crypto.randomUUID(); setConfirmingDisable(false); event.currentTarget.reset(); });
  }

  async function submitManualInjury(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const formData = new FormData(event.currentTarget);
    const injury = fieldsToInjury(formData, "manual_injury");
    if (!injury) { setFeedback({ kind: "error", message: "请勾选并填写完整的伤病时间。" }); return; }
    if (injury === undefined) { setFeedback({ kind: "error", message: "请填写有效的伤病 WP 开始和结束时间。" }); return; }
    finish(await createManualInjury({ horseId, injury }), () => event.currentTarget.reset());
  }

  return <section className="mt-8 border-t border-stone-800 pt-6">
    <div className="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between"><div><h2 className="text-xl font-semibold text-amber-200">体力、赛后状态与伤病</h2><p className="mt-2 max-w-3xl text-sm leading-6 text-stone-400">{currentStamina === null ? "当前未启用体力管理。未启用不等于体力为 0；伤病仍可独立存在。" : "体力管理已启用。0 / 100 表示体力耗尽，仍不会自动阻止报名。"}</p></div><div className={`w-fit rounded-xl border px-4 py-3 ${currentStamina === null ? "border-stone-700 bg-stone-950/60" : "border-amber-300/35 bg-amber-300/5"}`}><p className="text-xs text-stone-500">当前体力</p><p className="mt-1 text-xl font-semibold text-amber-100">{staminaLabel(currentStamina)}</p></div></div>
    <FeedbackMessage feedback={feedback} />

    {isGM && <div className="mt-6 grid gap-5 xl:grid-cols-2"><details className="rounded-xl border border-amber-300/25 bg-stone-950/45 p-5"><summary className="cursor-pointer font-semibold text-amber-100">{currentStamina === null ? "启用体力管理" : "调整体力或停止管理"}</summary><p className="mt-3 text-sm leading-6 text-stone-400">{currentStamina === null ? "可启用为任意 0–100 的整数；建议值 100 仅为输入辅助，不会自动写入。" : "可调整为 0–100，或停止体力管理。相同状态不会写入健康事件。"}</p><form className="mt-5 space-y-4" onSubmit={submitStamina}><label className="admin-label">操作<select className="admin-input" name="stamina_mode" onChange={(event) => { setStaminaMode(event.target.value as "set" | "disable"); setConfirmingDisable(false); }} value={staminaMode}><option value="set">{currentStamina === null ? "启用体力管理" : "调整体力"}</option>{currentStamina !== null && <option value="disable">停止体力管理（设为未启用）</option>}</select></label>{staminaMode === "set" ? <label className="admin-label">目标体力（0–100）<input className="admin-input" defaultValue={currentStamina ?? 100} inputMode="numeric" min="0" max="100" name="stamina_after" placeholder="例如：70；0 是合法值" required type="number" /></label> : <input name="stamina_after" type="hidden" value="" />}<label className="admin-label">调整原因<textarea className="admin-input min-h-20" name="reason" required /></label>{confirmingDisable && staminaMode === "disable" && <p className="rounded-lg border border-red-400/35 bg-red-400/5 p-3 text-sm leading-6 text-red-100">停止后，该马匹 将不再显示当前体力；已有体力历史不会删除。</p>}<button className={staminaMode === "disable" ? "inline-flex items-center justify-center rounded-lg border border-red-400/60 px-4 py-2.5 text-sm font-semibold text-red-200 hover:bg-red-400/10" : "admin-button"} type="submit">{staminaMode === "disable" ? confirmingDisable ? "确认停止体力管理" : "停止体力管理" : currentStamina === null ? "启用体力管理" : "记录体力调整"}</button></form></details>
      <details className="rounded-xl border border-red-400/25 bg-stone-950/45 p-5"><summary className="cursor-pointer font-semibold text-red-100">新增手动伤病</summary><p className="mt-3 text-sm leading-6 text-stone-400">伤病与体力管理相互独立。此操作只建立伤病事件，不会自动改变体力。</p><form className="mt-5 space-y-4" onSubmit={submitManualInjury}><InjuryFields defaultWp={createInjuryDefault} prefix="manual_injury" /><button className="inline-flex items-center justify-center rounded-lg border border-red-400/60 px-4 py-2.5 text-sm font-semibold text-red-200 hover:bg-red-400/10" type="submit">创建伤病事件</button></form></details></div>}

    <section className="mt-8"><h3 className="font-semibold text-amber-200">伤病</h3><p className="mt-2 text-sm text-stone-400">有效伤病会阻止其开始至结束周（含）的赛程；已恢复、已作废状态均作为历史保留。</p><div className="mt-4 space-y-4">{injuries.map((injury) => <InjuryCard injury={injury} isGM={isGM} key={injury.id} horseId={horseId} onResult={finish} />)}{!injuries.length && <p className="rounded-xl border border-stone-800 bg-stone-950/50 p-5 text-sm text-stone-500">暂无伤病记录。</p>}</div></section>

    <section className="mt-8"><h3 className="font-semibold text-amber-200">健康历史</h3><p className="mt-2 text-sm text-stone-400">赛后状态与人工体力调整均按实际记录展示。公开页面不显示 GM 备注、处理人或私密更正理由。</p><div className="mt-4 space-y-4">{events.map((healthEvent) => <HealthEventCard defaultWp={createInjuryDefault} event={healthEvent} horseId={horseId} isGM={isGM} key={healthEvent.id} onResult={finish} />)}{!events.length && <p className="rounded-xl border border-stone-800 bg-stone-950/50 p-5 text-sm text-stone-500">暂无健康事件。</p>}</div></section>
  </section>;
}

function InjuryCard({ injury, horseId, isGM, onResult }: { injury: HealthInjury; horseId: string; isGM: boolean; onResult: (result: HealthActionResult) => void }) {
  const [reason, setReason] = useState("");
  const [confirming, setConfirming] = useState<"resolve" | "void" | null>(null);
  const [busy, setBusy] = useState(false);
  async function act(kind: "resolve" | "void") { setBusy(true); const result = kind === "resolve" ? await resolveHorseInjury({ horseId, injuryId: injury.id, reason }) : await voidHorseInjury({ horseId, injuryId: injury.id, reason }); setBusy(false); setConfirming(null); onResult(result); }
  const canVoid = injury.status !== "VOIDED";
  return <article className={`rounded-xl border p-5 ${injury.status === "ACTIVE" ? "border-red-400/35 bg-red-400/5" : "border-stone-800 bg-stone-950/50"}`}><div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between"><div><p className="font-semibold text-stone-100">{formatInjuryStatus(injury.status)}</p><p className="mt-2 text-sm text-stone-300">{formatWpTime(injury.startYear, injury.startMonth, injury.startWeek)} 至 {formatWpTime(injury.endYear, injury.endMonth, injury.endWeek)}</p></div><span className={`w-fit rounded-full border px-3 py-1 text-xs font-semibold ${injury.status === "ACTIVE" ? "border-red-400/40 text-red-100" : injury.status === "VOIDED" ? "border-stone-700 text-stone-500" : "border-emerald-400/40 text-emerald-100"}`}>{formatInjuryStatus(injury.status)}</span></div>{injury.notes && <p className="mt-4 whitespace-pre-wrap text-sm leading-6 text-stone-300">{injury.notes}</p>}{isGM && <div className="mt-4 border-t border-stone-800 pt-4 text-xs leading-5 text-stone-500">{injury.sourceHealthEventId ? "来源：赛后健康事件" : "来源：GM 手动伤病"}{injury.resolvedAt && <p className="mt-1">已恢复：{injury.resolutionReason || "—"}</p>}{injury.voidedAt && <p className="mt-1">已作废：{injury.voidReason || "—"}</p>}</div>}{isGM && canVoid && <div className="mt-5"><label className="admin-label">GM 原因<textarea className="admin-input min-h-20" onChange={(event) => setReason(event.target.value)} value={reason} /></label>{confirming ? <div className="mt-3 rounded-lg border border-amber-300/40 bg-amber-300/5 p-3 text-sm text-amber-100"><p>确认{confirming === "resolve" ? "标记伤病恢复" : "作废这条伤病"}吗？历史记录会保留。</p><div className="mt-3 flex flex-wrap gap-2"><button className="admin-button" disabled={!reason.trim() || busy} onClick={() => act(confirming)} type="button">{busy ? "正在处理…" : "确认执行"}</button><button className="rounded-lg border border-stone-600 px-4 py-2.5 text-sm text-stone-200" onClick={() => setConfirming(null)} type="button">取消</button></div></div> : <div className="mt-3 flex flex-wrap gap-2">{injury.status === "ACTIVE" && <button className="rounded-lg border border-emerald-400/55 px-4 py-2.5 text-sm font-semibold text-emerald-100 hover:bg-emerald-400/10" onClick={() => setConfirming("resolve")} type="button">确认恢复</button>}<button className="rounded-lg border border-red-400/55 px-4 py-2.5 text-sm font-semibold text-red-200 hover:bg-red-400/10" onClick={() => setConfirming("void")} type="button">作废伤病</button></div>}</div>}</article>;
}

function HealthEventCard({ event, horseId, isGM, defaultWp, onResult }: { event: HorseHealthEvent; horseId: string; isGM: boolean; defaultWp: { year: number; month: number; week: number }; onResult: (result: HealthActionResult) => void }) {
  const correctionRequestId = useRef(crypto.randomUUID());
  const [feedback, setFeedback] = useState<Feedback>(null);
  const [voidReason, setVoidReason] = useState("");
  const [confirmVoid, setConfirmVoid] = useState(false);
  const [busy, setBusy] = useState(false);
  async function correct(eventForm: FormEvent<HTMLFormElement>) { eventForm.preventDefault(); const data = new FormData(eventForm.currentTarget); const staminaAfter = parseOptionalStamina(String(data.get("stamina_after") ?? "")); const injury = fieldsToInjury(data, "correction_injury"); if (staminaAfter === undefined || injury === undefined) { setFeedback({ kind: "error", message: "请填写有效体力与完整伤病时间。" }); return; } setBusy(true); const result = await correctLatestHorseHealthEvent({ horseId, healthEventId: event.id, staminaAfter, notes: String(data.get("notes") ?? ""), reason: String(data.get("reason") ?? ""), requestId: correctionRequestId.current, injury }); setBusy(false); setFeedback({ kind: result.ok ? "success" : "error", message: result.message }); onResult(result); if (result.ok) correctionRequestId.current = crypto.randomUUID(); }
  async function voidEvent() { setBusy(true); const result = await voidLatestHorseHealthEvent({ horseId, healthEventId: event.id, reason: voidReason }); setBusy(false); setConfirmVoid(false); setFeedback({ kind: result.ok ? "success" : "error", message: result.message }); onResult(result); }
  const canControl = isGM && event.status === "ACTIVE" && event.isLatestActive;
  const unmanagedPostRace = event.eventType === "POST_RACE" && event.staminaBefore === null;
  return <article className={`rounded-xl border p-5 ${event.status === "VOIDED" ? "border-stone-800 bg-stone-950/60 text-stone-500" : "border-stone-800 bg-stone-950/45"}`}><div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between"><div><p className="font-semibold text-stone-100">{formatHorseHealthEventType(event.eventType)}</p><p className="mt-1 text-sm text-stone-400">{formatWpTime(event.wpYear, event.wpMonth, event.wpWeek)} · {eventStaminaLabel(event)}</p></div><span className={`w-fit rounded-full border px-3 py-1 text-xs font-semibold ${event.status === "VOIDED" ? "border-stone-700 text-stone-500" : "border-emerald-400/40 text-emerald-100"}`}>{formatHorseHealthEventStatus(event.status)}</span></div>{isGM && event.notes && <p className="mt-4 rounded border border-stone-700 bg-stone-950/70 p-3 text-sm leading-6 text-stone-300">GM 备注：{event.notes}</p>}{isGM && event.voidReason && <p className="mt-4 rounded border border-red-400/25 bg-red-400/5 p-3 text-sm leading-6 text-red-100">作废原因：{event.voidReason}</p>}{isGM && event.status === "ACTIVE" && !event.isLatestActive && <p className="mt-4 rounded border border-amber-300/25 bg-amber-300/5 p-3 text-sm leading-6 text-amber-100">这不是最新有效健康事件。请先处理之后的健康记录，避免破坏体力事件链。</p>}{canControl && <details className="mt-5 rounded-lg border border-amber-300/25 bg-amber-300/5 p-4"><summary className="cursor-pointer text-sm font-semibold text-amber-100">纠正或作废最新健康事件</summary><p className="mt-2 text-xs leading-5 text-stone-400">纠错会作废原事件并写入替代事件；作废会回退当前体力。赛后事件不可借此启用或停止体力管理。</p><form className="mt-4 space-y-4" onSubmit={correct}>{unmanagedPostRace ? <><input name="stamina_after" type="hidden" value="" /><p className="rounded border border-stone-700 bg-stone-950/60 p-3 text-sm text-stone-300">此马匹 的赛后事件保持为“未启用体力管理”；纠错不能在这里启用或停止管理。</p></> : <label className="admin-label">纠正后的体力（留空代表未启用）<input className="admin-input" defaultValue={event.staminaAfter ?? ""} min="0" max="100" name="stamina_after" type="number" /></label>}<label className="admin-label">GM 备注<textarea className="admin-input min-h-20" defaultValue={event.notes ?? ""} name="notes" /></label>{event.eventType === "POST_RACE" && <InjuryFields defaultWp={defaultWp} injury={event.sourceInjury} prefix="correction_injury" />}<label className="admin-label">纠错原因<textarea className="admin-input min-h-20" name="reason" required /></label><button className="admin-button" disabled={busy} type="submit">{busy ? "正在纠错…" : "确认纠错"}</button></form><div className="mt-5 border-t border-red-400/25 pt-4"><label className="admin-label">作废原因<textarea className="admin-input min-h-20" onChange={(next) => setVoidReason(next.target.value)} value={voidReason} /></label>{confirmVoid ? <div className="mt-3 rounded border border-red-400/40 bg-red-400/5 p-3 text-sm text-red-100"><p>第二次确认：作废会回退当前体力，并作废该事件产生的伤病。</p><div className="mt-3 flex flex-wrap gap-2"><button className="inline-flex items-center justify-center rounded-lg border border-red-400/60 px-4 py-2.5 text-sm font-semibold text-red-200" disabled={!voidReason.trim() || busy} onClick={voidEvent} type="button">{busy ? "正在作废…" : "确认作废"}</button><button className="rounded-lg border border-stone-600 px-4 py-2.5 text-sm text-stone-200" onClick={() => setConfirmVoid(false)} type="button">取消</button></div></div> : <button className="mt-3 inline-flex items-center justify-center rounded-lg border border-red-400/60 px-4 py-2.5 text-sm font-semibold text-red-200 hover:bg-red-400/10" onClick={() => setConfirmVoid(true)} type="button">作废最新健康事件</button>}</div><FeedbackMessage feedback={feedback} /></details>}</article>;
}
