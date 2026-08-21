"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";

import {
  activateBreedingCandidate,
  deactivateBreedingCandidate,
} from "@/app/admin/breeding/actions";

type CandidateState = {
  candidateType: "STALLION" | "BROODMARE";
  isActive: boolean;
  notes: string | null;
} | null;

type BreedingCandidateControlsProps = {
  horseId: string;
  lifeStage: string;
  sex: string;
  candidate: CandidateState;
  compact?: boolean;
};

function candidateLabel(sex: string) {
  return sex === "MALE" ? "候选种牡马" : "候选繁殖牝马";
}

export function BreedingCandidateControls({
  horseId,
  lifeStage,
  sex,
  candidate,
  compact = false,
}: BreedingCandidateControlsProps) {
  const router = useRouter();
  const [pending, startTransition] = useTransition();
  const [notes, setNotes] = useState(candidate?.notes ?? "");
  const [reason, setReason] = useState("");
  const [confirmDeactivate, setConfirmDeactivate] = useState(false);
  const [message, setMessage] = useState<string | null>(null);

  if (lifeStage !== "RETIRED") {
    return <p className="text-sm leading-6 text-stone-500">仅已退役 Horse 可加入繁育候选。</p>;
  }
  if (sex === "GELDING") {
    return <p className="text-sm leading-6 text-stone-500">不具备繁育候选资格：阉马不能成为候选种牡马或繁殖牝马。</p>;
  }
  if (sex !== "MALE" && sex !== "FEMALE") {
    return <p className="text-sm leading-6 text-stone-500">当前 Horse 性别资料无效，不能加入繁育候选。</p>;
  }

  const activate = () => {
    setMessage(null);
    startTransition(async () => {
      const result = await activateBreedingCandidate(horseId, notes);
      setMessage(result.ok ? result.notice : result.message);
      if (result.ok) router.refresh();
    });
  };

  const deactivate = () => {
    setMessage(null);
    startTransition(async () => {
      const result = await deactivateBreedingCandidate(horseId, reason);
      setMessage(result.ok ? result.notice : result.message);
      if (result.ok) {
        setConfirmDeactivate(false);
        router.refresh();
      }
    });
  };

  if (candidate?.isActive) {
    return (
      <div className={compact ? "space-y-3" : "mt-4 space-y-4 rounded-lg border border-emerald-400/30 bg-emerald-400/5 p-4"}>
        <div className="flex flex-wrap items-center gap-2">
          <span className="rounded-full border border-emerald-400/40 px-2.5 py-1 text-xs font-semibold text-emerald-100">{candidate.candidateType === "STALLION" ? "种牡马候选" : "繁殖牝马候选"}</span>
          <span className="text-sm text-emerald-100">使用中</span>
        </div>
        {candidate.notes && <p className="text-sm leading-6 text-stone-300">备注：{candidate.notes}</p>}
        {confirmDeactivate ? (
          <div className="rounded-lg border border-red-400/35 bg-red-400/5 p-4">
            <label className="admin-label">停用原因（可选）
              <textarea className="admin-input min-h-20" onChange={(event) => setReason(event.target.value)} placeholder="例如：本季不再开放为内部繁育候选" value={reason} />
            </label>
            <p className="mt-3 text-sm leading-6 text-red-100">确认后将从新建幼驹的默认候选中移除；Horse 本身继续保持 RETIRED，已有血统快照不受影响。</p>
            <div className="mt-4 flex flex-wrap gap-3">
              <button className="inline-flex items-center justify-center rounded-lg border border-stone-600 px-4 py-2.5 text-sm font-semibold text-stone-200 hover:border-amber-300" disabled={pending} onClick={() => setConfirmDeactivate(false)} type="button">取消</button>
              <button className="inline-flex items-center justify-center rounded-lg border border-red-400/60 px-4 py-2.5 text-sm font-semibold text-red-200 hover:bg-red-400/10 disabled:cursor-not-allowed disabled:opacity-60" disabled={pending} onClick={deactivate} type="button">{pending ? "移出中…" : "确认移出候选"}</button>
            </div>
          </div>
        ) : (
          <button className="inline-flex items-center justify-center rounded-lg border border-red-400/60 px-4 py-2.5 text-sm font-semibold text-red-200 hover:bg-red-400/10 disabled:cursor-not-allowed disabled:opacity-60" disabled={pending} onClick={() => setConfirmDeactivate(true)} type="button">移出候选</button>
        )}
        {message && <p aria-live="polite" className="text-sm text-amber-100">{message}</p>}
      </div>
    );
  }

  return (
    <div className={compact ? "space-y-3" : "mt-4 space-y-4 rounded-lg border border-stone-800 bg-stone-950/60 p-4"}>
      {candidate && <p className="text-sm text-stone-400">该 Horse 曾是候选，当前已停用。重新加入会恢复为 {candidateLabel(sex)}。</p>}
      <label className="admin-label">候选备注（可选）
        <textarea className="admin-input min-h-20" onChange={(event) => setNotes(event.target.value)} placeholder="例如：GM 确认可作为内部繁育候选" value={notes} />
      </label>
      <button className="admin-button" disabled={pending} onClick={activate} type="button">{pending ? "加入中…" : sex === "MALE" ? "加入候选种牡马" : "加入候选繁殖牝马"}</button>
      {message && <p aria-live="polite" className="text-sm text-amber-100">{message}</p>}
    </div>
  );
}
