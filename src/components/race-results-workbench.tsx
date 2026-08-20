"use client";

import { useMemo, useState } from "react";
import { useRouter } from "next/navigation";

import { correctRaceResult, recordRaceResult, voidRaceResult } from "@/app/admin/race-results/actions";
import { ActionForm } from "@/components/action-form";
import { formatDateTime, formatGameMoney, formatRaceGrade, formatRaceKind, formatRaceResultStatus, formatWpTime } from "@/lib/format";

export type ResultActualRaceOption = {
  id: string;
  wp_year: number;
  wp_month: number;
  wp_week: number;
  race_name: string;
  grade: string | null;
};

export type RaceResultCandidate = {
  id: string;
  horseId: string;
  horseName: string;
  horseNumber: number | string;
  ownerName: string;
  wpYear: number;
  wpMonth: number;
  wpWeek: number;
  raceKind: string;
  raceCatalogId: string | null;
  raceLabel: string | null;
  jockey: string | null;
  runningStyle: string | null;
  source: "PLAYER Request" | "GM Direct";
  recommendation: "强推荐" | "同周候选" | "相邻周候选" | "其他待录赛程" | "未来赛程";
};

export type RaceResultHistoryItem = RaceResultCandidate & {
  resultId: string;
  status: string;
  actualRaceId: string;
  finishPosition: number;
  prizeAmount: string;
  actualJockey: string | null;
  actualRunningStyle: string | null;
  gmNote: string | null;
  recordedAt: string;
  voidedAt: string | null;
  voidReason: string | null;
};

type Draft = {
  finishPosition: string;
  prizeAmount: string;
  actualJockey: string;
  actualRunningStyle: string;
  gmNote: string;
};

type SaveState = { kind: "idle" | "saving" | "success" | "error"; message?: string };

type RaceResultsWorkbenchProps = {
  actualRace: {
    id: string;
    wpYear: number;
    wpMonth: number;
    wpWeek: number;
    raceKind: string;
    raceCatalogId: string | null;
    raceName: string;
    grade: string | null;
  };
  candidates: RaceResultCandidate[];
  confirmedResults: RaceResultHistoryItem[];
  voidedResults: RaceResultHistoryItem[];
  actualRaces: ResultActualRaceOption[];
};

function samePlanRace(candidate: RaceResultCandidate, actualRace: RaceResultsWorkbenchProps["actualRace"]) {
  if (candidate.raceKind !== actualRace.raceKind) return false;
  if (candidate.raceKind === "CATALOG") return candidate.raceCatalogId === actualRace.raceCatalogId;
  return (candidate.raceLabel ?? "").trim().toLocaleLowerCase() === actualRace.raceName.trim().toLocaleLowerCase();
}

function planRaceName(candidate: RaceResultCandidate) {
  return candidate.raceLabel || formatRaceKind(candidate.raceKind);
}

function draftFor(candidate: RaceResultCandidate): Draft {
  return {
    finishPosition: "",
    prizeAmount: "",
    actualJockey: candidate.jockey ?? "",
    actualRunningStyle: candidate.runningStyle ?? "",
    gmNote: "",
  };
}

function ResultFacts({ result, actualRace }: { result: RaceResultHistoryItem; actualRace: RaceResultsWorkbenchProps["actualRace"] }) {
  return <div className="mt-4 grid gap-3 text-sm sm:grid-cols-2 xl:grid-cols-4">
    <div><p className="text-xs text-stone-500">名次</p><p className="mt-1 font-semibold text-amber-100">{result.finishPosition} 着</p></div>
    <div><p className="text-xs text-stone-500">Winning Post 实际赏金</p><p className="mt-1 font-semibold text-amber-100">{formatGameMoney(result.prizeAmount)}</p></div>
    <div><p className="text-xs text-stone-500">实际骑手 / 跑法</p><p className="mt-1 text-stone-200">{result.actualJockey || "未指定"} · {result.actualRunningStyle || "未指定"}</p></div>
    <div><p className="text-xs text-stone-500">录入时间</p><p className="mt-1 text-stone-200">{formatDateTime(result.recordedAt)}</p></div>
    {(result.wpYear !== actualRace.wpYear || result.wpMonth !== actualRace.wpMonth || result.wpWeek !== actualRace.wpWeek) && <p className="sm:col-span-2 xl:col-span-4 rounded border border-amber-300/30 bg-amber-300/5 px-3 py-2 text-xs leading-5 text-amber-100">这条赛果当前关联到另一场 Actual Race；赛前计划仅用于对比。</p>}
  </div>;
}

export function RaceResultsWorkbench({ actualRace, candidates, confirmedResults, voidedResults, actualRaces }: RaceResultsWorkbenchProps) {
  const router = useRouter();
  const [selected, setSelected] = useState<Set<string>>(() => new Set());
  const [drafts, setDrafts] = useState<Record<string, Draft>>({});
  const [saveStates, setSaveStates] = useState<Record<string, SaveState>>({});
  const [saving, setSaving] = useState(false);

  const readyCandidates = useMemo(() => candidates.filter((candidate) => {
    const draft = drafts[candidate.id];
    return selected.has(candidate.id) && Boolean(draft && /^\d+$/.test(draft.finishPosition) && Number(draft.finishPosition) >= 1 && Number(draft.finishPosition) <= 99 && /^\d+$/.test(draft.prizeAmount));
  }), [candidates, drafts, selected]);

  function toggleCandidate(candidate: RaceResultCandidate) {
    setSelected((current) => {
      const next = new Set(current);
      if (next.has(candidate.id)) {
        next.delete(candidate.id);
      } else {
        next.add(candidate.id);
        setDrafts((existing) => existing[candidate.id] ? existing : { ...existing, [candidate.id]: draftFor(candidate) });
      }
      return next;
    });
  }

  function updateDraft(candidateId: string, field: keyof Draft, value: string) {
    setDrafts((current) => ({ ...current, [candidateId]: { ...(current[candidateId] ?? { finishPosition: "", prizeAmount: "", actualJockey: "", actualRunningStyle: "", gmNote: "" }), [field]: value } }));
  }

  async function saveReadyResults() {
    if (!readyCandidates.length || saving) return;
    setSaving(true);
    let successCount = 0;
    for (const candidate of readyCandidates) {
      const draft = drafts[candidate.id];
      setSaveStates((current) => ({ ...current, [candidate.id]: { kind: "saving", message: "正在保存…" } }));
      const outcome = await recordRaceResult({
        confirmedRaceEntryId: candidate.id,
        actualRaceId: actualRace.id,
        finishPosition: draft.finishPosition,
        prizeAmount: draft.prizeAmount,
        actualJockey: draft.actualJockey,
        actualRunningStyle: draft.actualRunningStyle,
        gmNote: draft.gmNote,
      });
      if (outcome.ok) successCount += 1;
      setSaveStates((current) => ({ ...current, [candidate.id]: { kind: outcome.ok ? "success" : "error", message: outcome.message } }));
    }
    setSaving(false);
    if (successCount) router.refresh();
  }

  return (
    <div className="space-y-8">
      <section>
        <div className="flex flex-col gap-3 border-b border-stone-800 pb-4 sm:flex-row sm:items-end sm:justify-between">
          <div><h2 className="text-xl font-semibold text-amber-200">候选 Confirmed Entries</h2><p className="mt-2 text-sm leading-6 text-stone-400">系统只按时间和比赛事实推荐，不会自动绑定。已存在有效赛果的赛程已排除；VOIDED 历史不会阻止重新录入。</p></div>
          <p className="font-mono text-sm text-stone-500">已选 {selected.size} · 可保存 {readyCandidates.length}</p>
        </div>
        <div className="mt-5 space-y-4">
          {candidates.map((candidate) => {
            const isSelected = selected.has(candidate.id);
            const draft = drafts[candidate.id] ?? draftFor(candidate);
            const state = saveStates[candidate.id] ?? { kind: "idle" as const };
            const timeMismatch = candidate.wpYear !== actualRace.wpYear || candidate.wpMonth !== actualRace.wpMonth || candidate.wpWeek !== actualRace.wpWeek;
            const raceMismatch = !samePlanRace(candidate, actualRace);
            const jockeyMismatch = Boolean(draft.actualJockey && candidate.jockey && draft.actualJockey !== candidate.jockey);
            const styleMismatch = Boolean(draft.actualRunningStyle && candidate.runningStyle && draft.actualRunningStyle !== candidate.runningStyle);
            return <article className={`rounded-xl border p-5 ${isSelected ? "border-amber-300/50 bg-amber-300/5" : "border-stone-800 bg-stone-900"}`} key={candidate.id}>
              <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
                <label className="flex cursor-pointer items-start gap-3"><input checked={isSelected} className="mt-1 size-4 accent-amber-300" onChange={() => toggleCandidate(candidate)} type="checkbox" /><span><span className="font-semibold text-stone-100">{candidate.horseName} <span className="font-mono text-xs text-stone-500">#{candidate.horseNumber}</span></span><span className="mt-1 block text-sm text-stone-400">Owner：{candidate.ownerName} · {candidate.source}</span></span></label>
                <span className="w-fit rounded-full border border-stone-700 px-3 py-1 text-xs text-stone-300">{candidate.recommendation}</span>
              </div>
              <div className="mt-4 grid gap-3 rounded-lg border border-stone-800 bg-stone-950/50 p-4 text-sm sm:grid-cols-2 xl:grid-cols-4"><div><p className="text-xs text-stone-500">赛前计划时间</p><p className="mt-1 text-stone-200">{formatWpTime(candidate.wpYear, candidate.wpMonth, candidate.wpWeek)}</p></div><div><p className="text-xs text-stone-500">赛前计划比赛</p><p className="mt-1 text-stone-200">{planRaceName(candidate)}</p></div><div><p className="text-xs text-stone-500">计划骑手 / 跑法</p><p className="mt-1 text-stone-200">{candidate.jockey || "未指定"} · {candidate.runningStyle || "未指定"}</p></div><div><p className="text-xs text-stone-500">实际比赛</p><p className="mt-1 text-amber-100">{actualRace.raceName} {actualRace.grade ? formatRaceGrade(actualRace.grade) : ""}</p></div></div>
              {(timeMismatch || raceMismatch) && <p className="mt-3 rounded border border-amber-300/30 bg-amber-300/5 px-3 py-2 text-xs leading-5 text-amber-100">{timeMismatch && "实际比赛时间与赛前计划不同。"}{timeMismatch && raceMismatch && " "}{raceMismatch && "实际比赛与赛前计划不同。"} 这是提示，GM 可明确选择后录入。</p>}
              {isSelected && <div className="mt-5 grid gap-4 sm:grid-cols-2 xl:grid-cols-[8rem_minmax(10rem,1fr)_minmax(11rem,1fr)_minmax(9rem,min-content)_minmax(12rem,1.3fr)]"><label className="admin-label">名次<input className="admin-input" inputMode="numeric" max="99" min="1" onChange={(event) => updateDraft(candidate.id, "finishPosition", event.target.value)} placeholder="必填" type="number" value={draft.finishPosition} /></label><label className="admin-label">Winning Post 实际赏金<input className="admin-input" inputMode="numeric" min="0" onChange={(event) => updateDraft(candidate.id, "prizeAmount", event.target.value)} placeholder="必填，允许 0" type="text" value={draft.prizeAmount} /></label><label className="admin-label">实际骑手（可选）<input className="admin-input" onChange={(event) => updateDraft(candidate.id, "actualJockey", event.target.value)} value={draft.actualJockey} /></label><label className="admin-label">实际跑法（可选）<select className="admin-input" onChange={(event) => updateDraft(candidate.id, "actualRunningStyle", event.target.value)} value={draft.actualRunningStyle}><option value="">未指定</option><option value="逃">逃</option><option value="先">先</option><option value="差">差</option><option value="追">追</option></select></label><label className="admin-label sm:col-span-2 xl:col-span-1">GM Note（仅 GM）<input className="admin-input" onChange={(event) => updateDraft(candidate.id, "gmNote", event.target.value)} value={draft.gmNote} /></label></div>}
              {isSelected && (jockeyMismatch || styleMismatch) && <p className="mt-3 text-xs text-amber-100">{jockeyMismatch && "实际骑手与赛前计划不同。"}{jockeyMismatch && styleMismatch && " "}{styleMismatch && "实际跑法与赛前计划不同。"}</p>}
              {state.kind !== "idle" && <p className={`mt-4 text-sm ${state.kind === "error" ? "text-red-200" : state.kind === "success" ? "text-emerald-200" : "text-amber-100"}`}>{state.message}</p>}
            </article>;
          })}
          {!candidates.length && <p className="rounded-xl border border-stone-800 bg-stone-900 p-6 text-sm text-stone-500">当前没有可关联的已确认赛程。</p>}
        </div>
        <div className="mt-5 flex flex-col gap-3 rounded-xl border border-stone-800 bg-stone-900 p-5 sm:flex-row sm:items-center sm:justify-between"><p className="text-sm leading-6 text-stone-400">仅提交名次和实际赏金均完整的已选行。多条 RPC 不构成数据库事务，成功行会保留；失败行会保留输入与错误提示。</p><button className="admin-button shrink-0" disabled={!readyCandidates.length || saving} onClick={saveReadyResults} type="button">{saving ? "正在逐条保存…" : `保存全部已填写结果（${readyCandidates.length}）`}</button></div>
      </section>

      <section className="border-t border-stone-800 pt-8"><h2 className="text-xl font-semibold text-amber-200">当前有效赛果</h2><p className="mt-2 text-sm text-stone-400">赛前计划、实际比赛与实际赛果分开显示。纠错和作废均为单条、高风险操作。</p><div className="mt-5 space-y-5">{confirmedResults.map((result) => <ResultCard actualRace={actualRace} actualRaces={actualRaces} key={result.resultId} result={result} />)}{!confirmedResults.length && <p className="rounded-xl border border-stone-800 bg-stone-900 p-6 text-sm text-stone-500">该实际比赛尚未录入玩家马赛果。</p>}</div></section>

      <section className="border-t border-stone-800 pt-8"><h2 className="text-xl font-semibold text-stone-300">VOIDED 历史</h2><p className="mt-2 text-sm text-stone-500">作废记录仅 GM 可见，不会出现在公开赛果或 Horse 统计中。</p><div className="mt-5 space-y-4">{voidedResults.map((result) => <article className="rounded-xl border border-stone-800 bg-stone-950/60 p-5" key={result.resultId}><div className="flex flex-col gap-3 sm:flex-row sm:justify-between"><div><p className="font-semibold text-stone-200">{result.horseName} <span className="font-mono text-xs text-stone-500">#{result.horseNumber}</span></p><p className="mt-1 text-sm text-stone-500">Owner：{result.ownerName} · {formatRaceResultStatus(result.status)}</p></div><p className="text-sm text-stone-500">作废于 {formatDateTime(result.voidedAt)}</p></div><ResultFacts actualRace={actualRace} result={result} /><p className="mt-4 rounded border border-red-400/25 bg-red-400/5 p-3 text-sm leading-6 text-red-100">作废原因：{result.voidReason || "—"}</p></article>)}{!voidedResults.length && <p className="rounded-xl border border-stone-800 bg-stone-900 p-6 text-sm text-stone-500">暂无 VOIDED 历史。</p>}</div></section>
    </div>
  );
}

function ResultCard({ result, actualRace, actualRaces }: { result: RaceResultHistoryItem; actualRace: RaceResultsWorkbenchProps["actualRace"]; actualRaces: ResultActualRaceOption[] }) {
  const correct = correctRaceResult.bind(null, result.resultId);
  const voidResult = voidRaceResult.bind(null, result.resultId, actualRace.id);
  return <article className="rounded-xl border border-emerald-400/30 bg-emerald-400/5 p-5"><div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between"><div><p className="font-semibold text-stone-100">{result.horseName} <span className="font-mono text-xs text-stone-500">#{result.horseNumber}</span></p><p className="mt-1 text-sm text-stone-400">Owner：{result.ownerName} · {result.source}</p></div><span className="w-fit rounded-full border border-emerald-400/40 px-3 py-1 text-xs font-semibold text-emerald-100">{formatRaceResultStatus(result.status)}</span></div><div className="mt-4 grid gap-3 rounded-lg border border-stone-800 bg-stone-950/50 p-4 text-sm sm:grid-cols-2"><div><p className="text-xs text-stone-500">赛前计划</p><p className="mt-1 text-stone-200">{formatWpTime(result.wpYear, result.wpMonth, result.wpWeek)} · {planRaceName(result)}</p><p className="mt-1 text-stone-400">骑手：{result.jockey || "未指定"} · 跑法：{result.runningStyle || "未指定"}</p></div><div><p className="text-xs text-stone-500">实际比赛</p><p className="mt-1 text-amber-100">{formatWpTime(actualRace.wpYear, actualRace.wpMonth, actualRace.wpWeek)} · {actualRace.raceName} {actualRace.grade ? formatRaceGrade(actualRace.grade) : ""}</p></div></div><ResultFacts actualRace={actualRace} result={result} />{result.gmNote && <p className="mt-4 rounded border border-stone-700 bg-stone-950/60 p-3 text-sm leading-6 text-stone-300">GM Note：{result.gmNote}</p>}<div className="mt-5 grid gap-4 xl:grid-cols-2"><details className="rounded-lg border border-amber-300/25 bg-stone-950/40 p-4"><summary className="cursor-pointer text-sm font-semibold text-amber-100">纠错当前赛果</summary><p className="mt-2 text-xs leading-5 text-stone-400">只能修改实际比赛和赛果事实；不能修改 Horse 或 Confirmed Entry。请在确认前核对 Before / After 并填写原因。</p><ActionForm action={correct} className="mt-4 space-y-3" confirmation="确认纠错这条赛果吗？公开页面将只显示纠错后的当前事实。" pendingLabel="正在纠错…" submitLabel="确认纠错"><label className="admin-label">目标 Actual Race<select className="admin-input" defaultValue={result.actualRaceId} name="actual_race_id">{actualRaces.map((race) => <option key={race.id} value={race.id}>{formatWpTime(race.wp_year, race.wp_month, race.wp_week)} · {race.race_name} {race.grade ? formatRaceGrade(race.grade) : ""}</option>)}</select></label><div className="grid gap-3 sm:grid-cols-2"><label className="admin-label">名次<input className="admin-input" defaultValue={result.finishPosition} min="1" max="99" name="finish_position" required type="number" /></label><label className="admin-label">Winning Post 实际赏金<input className="admin-input" defaultValue={result.prizeAmount} inputMode="numeric" name="prize_amount" required type="text" /></label></div><label className="admin-label">实际骑手（可选）<input className="admin-input" defaultValue={result.actualJockey ?? ""} name="actual_jockey" /></label><label className="admin-label">实际跑法（可选）<select className="admin-input" defaultValue={result.actualRunningStyle ?? ""} name="actual_running_style"><option value="">未指定</option><option value="逃">逃</option><option value="先">先</option><option value="差">差</option><option value="追">追</option></select></label><label className="admin-label">GM Note（仅 GM）<textarea className="admin-input min-h-20" defaultValue={result.gmNote ?? ""} name="gm_note" /></label><label className="admin-label">纠错原因<textarea className="admin-input min-h-20" name="reason" required /></label></ActionForm></details><details className="rounded-lg border border-red-400/30 bg-red-400/5 p-4"><summary className="cursor-pointer text-sm font-semibold text-red-100">作废赛果</summary><p className="mt-2 text-xs leading-5 text-stone-300">作废不会删除历史记录。该赛果会从公开有效赛果中移除，之后可重新录入新的有效结果。</p><ActionForm action={voidResult} className="mt-4 space-y-3" confirmation="第二次确认：确定作废这条赛果吗？此操作会保留历史但从公开有效赛果移除。" pendingLabel="正在作废…" submitLabel="作废赛果" variant="danger"><label className="admin-label">作废原因<textarea className="admin-input min-h-20" name="reason" required /></label></ActionForm></details></div></article>;
}
