"use client";

import Link from "next/link";
import { useMemo, useState, useTransition } from "react";
import { useRouter } from "next/navigation";

import {
  createFoal,
  createPedigreeReference,
  deactivatePedigreeReference,
  updatePedigreeReference,
  type CreateFoalInput,
  type FoalParentSource,
  type PedigreeReferenceInput,
} from "@/app/admin/breeding/actions";
import { BreedingCandidateControls } from "@/components/breeding-candidate-controls";
import { formatHorseLifeStage } from "@/lib/format";

export type BreedingHorse = {
  id: string;
  horseNumber: string | number;
  foalName: string;
  nameKatakana: string | null;
  translatedName: string | null;
  sex: string;
  birthYear: string | number;
  lifeStage: string;
  sireName: string;
  sireLine: string;
};

export type BreedingCandidate = {
  id: string;
  horseId: string;
  candidateType: "STALLION" | "BROODMARE";
  isActive: boolean;
  notes: string | null;
  addedAt: string;
  deactivatedAt: string | null;
  horse: BreedingHorse | null;
};

export type PedigreeReference = {
  id: string;
  name: string;
  translatedName: string | null;
  sex: string | null;
  sireLine: string | null;
  sireName: string | null;
  damName: string | null;
  broodmareSireName: string | null;
  aliases: string[];
  notes: string | null;
  isActive: boolean;
};

type GameState = { currentWpYear: string | number } | null;
type Tab = "candidates" | "references" | "foals";

type BreedingWorkbenchProps = {
  candidates: BreedingCandidate[];
  references: PedigreeReference[];
  gameState: GameState;
  initialTab?: string;
};

const sourceLabels: Record<FoalParentSource, string> = {
  INTERNAL: "内部马匹",
  REFERENCE: "外部资料",
  MANUAL: "手动",
};

function canonicalName(horse: BreedingHorse | null | undefined) {
  if (!horse) return "马匹";
  return horse.nameKatakana || horse.translatedName || horse.foalName;
}

function displayHorse(horse: BreedingHorse | null | undefined) {
  if (!horse) return "马匹资料不可用";
  const canonical = canonicalName(horse);
  return horse.translatedName && horse.translatedName !== canonical
    ? `${canonical} · ${horse.translatedName}`
    : canonical;
}

function sexLabel(sex: string | null | undefined) {
  return sex === "MALE" ? "牡" : sex === "FEMALE" ? "牝" : sex === "GELDING" ? "阉" : "未知";
}

function sourceBadge(source: FoalParentSource) {
  const color = source === "INTERNAL"
    ? "border-emerald-400/40 bg-emerald-400/10 text-emerald-100"
    : source === "REFERENCE"
      ? "border-sky-400/40 bg-sky-400/10 text-sky-100"
      : "border-stone-600 bg-stone-800 text-stone-200";
  return <span className={`rounded-full border px-2.5 py-1 text-xs font-semibold ${color}`}>{sourceLabels[source]}</span>;
}

function ParentSourceSwitch({
  parent,
  source,
  setSource,
}: {
  parent: "sire" | "dam";
  source: FoalParentSource;
  setSource: (source: FoalParentSource) => void;
}) {
  return <div className="flex flex-wrap gap-2">{(["INTERNAL", "REFERENCE", "MANUAL"] as FoalParentSource[]).map((value) => <button className={`rounded-lg border px-3 py-2 text-sm font-semibold ${source === value ? "border-amber-300 bg-amber-300/10 text-amber-100" : "border-stone-700 text-stone-300 hover:border-stone-500"}`} key={value} onClick={() => setSource(value)} type="button">{value === "INTERNAL" ? (parent === "sire" ? "内部候选种牡马" : "内部候选繁殖牝马") : value === "REFERENCE" ? "外部血统资料" : "手动输入"}</button>)}</div>;
}

function emptyReference(): PedigreeReferenceInput {
  return {
    name: "",
    translatedName: "",
    sex: "",
    sireLine: "",
    sireName: "",
    damName: "",
    broodmareSireName: "",
    aliases: [],
    notes: "",
  };
}

function referenceInput(reference: PedigreeReference): PedigreeReferenceInput {
  return {
    referenceId: reference.id,
    name: reference.name,
    translatedName: reference.translatedName ?? "",
    sex: reference.sex ?? "",
    sireLine: reference.sireLine ?? "",
    sireName: reference.sireName ?? "",
    damName: reference.damName ?? "",
    broodmareSireName: reference.broodmareSireName ?? "",
    aliases: reference.aliases,
    notes: reference.notes ?? "",
  };
}

function ReferenceEditor({
  initial,
  onClose,
  onSaved,
}: {
  initial: PedigreeReferenceInput;
  onClose: () => void;
  onSaved: (message: string) => void;
}) {
  const router = useRouter();
  const [form, setForm] = useState(initial);
  const [aliasDraft, setAliasDraft] = useState("");
  const [pending, startTransition] = useTransition();
  const [message, setMessage] = useState<string | null>(null);
  const isEditing = Boolean(initial.referenceId);

  const update = <K extends keyof PedigreeReferenceInput>(key: K, value: PedigreeReferenceInput[K]) => {
    setForm((current) => ({ ...current, [key]: value }));
  };

  const addAlias = () => {
    const values = aliasDraft.split(/[\n,]/).map((value) => value.trim()).filter(Boolean);
    if (!values.length) return;
    setForm((current) => ({ ...current, aliases: Array.from(new Set([...current.aliases, ...values])) }));
    setAliasDraft("");
  };

  const save = () => {
    setMessage(null);
    startTransition(async () => {
      const result = isEditing ? await updatePedigreeReference(form) : await createPedigreeReference(form);
      if (!result.ok) {
        setMessage(result.message);
        return;
      }
      onSaved(result.notice);
      router.refresh();
    });
  };

  return (
    <section className="rounded-xl border border-amber-300/35 bg-amber-300/5 p-5 sm:p-6">
      <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <div>
          <p className="text-xs font-semibold tracking-[0.18em] text-amber-300">GM · 血统资料</p>
          <h3 className="mt-1 text-xl font-semibold text-stone-100">{isEditing ? "编辑外部血统资料" : "新增外部血统资料"}</h3>
        </div>
        <button className="w-fit text-sm text-stone-400 hover:text-amber-100" disabled={pending} onClick={onClose} type="button">关闭</button>
      </div>
      <p className="mt-3 text-sm leading-6 text-stone-400">资料库用于输入辅助，不是新建幼驹的硬性前提。修改资料库不会改写已经创建马匹的历史血统快照。</p>
      <div className="mt-6 grid gap-4 md:grid-cols-2">
        <label className="admin-label">标准名称 *
          <input className="admin-input" onChange={(event) => update("name", event.target.value)} required value={form.name} />
        </label>
        <label className="admin-label">译名
          <input className="admin-input" onChange={(event) => update("translatedName", event.target.value)} value={form.translatedName} />
        </label>
        <label className="admin-label">性别
          <select className="admin-input" onChange={(event) => update("sex", event.target.value)} value={form.sex}>
            <option value="">未知</option><option value="MALE">牡</option><option value="FEMALE">牝</option><option value="GELDING">阉</option>
          </select>
        </label>
        <label className="admin-label">父系
          <input className="admin-input" onChange={(event) => update("sireLine", event.target.value)} placeholder="例如：Halo系" value={form.sireLine} />
        </label>
        <label className="admin-label">父马
          <input className="admin-input" onChange={(event) => update("sireName", event.target.value)} value={form.sireName} />
        </label>
        <label className="admin-label">母马
          <input className="admin-input" onChange={(event) => update("damName", event.target.value)} value={form.damName} />
        </label>
        <label className="admin-label">母父
          <input className="admin-input" onChange={(event) => update("broodmareSireName", event.target.value)} value={form.broodmareSireName} />
        </label>
        <label className="admin-label">别名
          <div className="mt-2 rounded-lg border border-stone-700 bg-stone-950 p-2">
            <div className="flex flex-wrap gap-2">{form.aliases.map((alias) => <button className="rounded-full border border-stone-600 px-2.5 py-1 text-xs text-stone-200 hover:border-red-300 hover:text-red-200" key={alias} onClick={() => update("aliases", form.aliases.filter((value) => value !== alias))} type="button">{alias} ×</button>)}</div>
            <div className="mt-2 flex gap-2"><input className="min-w-0 flex-1 bg-transparent px-1 py-1 text-sm text-stone-100 outline-none placeholder:text-stone-600" onChange={(event) => setAliasDraft(event.target.value)} onKeyDown={(event) => { if (event.key === "Enter") { event.preventDefault(); addAlias(); } }} placeholder="输入别名后按 Enter" value={aliasDraft} /><button className="rounded-md border border-stone-600 px-3 text-sm text-stone-200 hover:border-amber-300" onClick={addAlias} type="button">添加</button></div>
          </div>
        </label>
        <label className="admin-label md:col-span-2">GM 备注
          <textarea className="admin-input min-h-24" onChange={(event) => update("notes", event.target.value)} value={form.notes} />
        </label>
      </div>
      <div className="mt-6 flex flex-wrap gap-3"><button className="admin-button" disabled={pending} onClick={save} type="button">{pending ? "保存中…" : isEditing ? "保存资料" : "创建资料"}</button><button className="inline-flex items-center justify-center rounded-lg border border-stone-600 px-4 py-2.5 text-sm font-semibold text-stone-200 hover:border-amber-300" disabled={pending} onClick={onClose} type="button">取消</button></div>
      {message && <p aria-live="polite" className="mt-4 text-sm text-red-100">{message}</p>}
    </section>
  );
}

function CandidateSearch({
  label,
  candidates,
  selectedId,
  onSelected,
}: {
  label: string;
  candidates: BreedingCandidate[];
  selectedId: string | null;
  onSelected: (id: string | null) => void;
}) {
  const [query, setQuery] = useState("");
  const selected = candidates.find((candidate) => candidate.horseId === selectedId) ?? null;
  const filtered = useMemo(() => {
    const normalized = query.trim().toLocaleLowerCase();
    if (!normalized) return candidates;
    return candidates.filter((candidate) => {
      const horse = candidate.horse;
      return [horse?.nameKatakana, horse?.translatedName, horse?.foalName, String(horse?.horseNumber ?? "")]
        .filter(Boolean).join(" ").toLocaleLowerCase().includes(normalized);
    });
  }, [candidates, query]);

  return <div className="space-y-3"><label className="admin-label">{label}<input className="admin-input" onChange={(event) => setQuery(event.target.value)} placeholder="搜索正式名、译名、幼驹名或马号" value={query} /></label>{selected && <div className="flex items-start justify-between gap-3 rounded-lg border border-emerald-400/35 bg-emerald-400/5 p-4"><div><p className="font-semibold text-emerald-100">{displayHorse(selected.horse)}</p><p className="mt-1 text-sm text-stone-400">#{selected.horse?.horseNumber} · {selected.horse?.sireLine || "父系未记录"}</p></div><button className="text-sm text-stone-300 hover:text-red-200" onClick={() => onSelected(null)} type="button">清除</button></div>}<div className="max-h-56 space-y-2 overflow-y-auto rounded-lg border border-stone-800 bg-stone-950/60 p-2">{filtered.map((candidate) => <button className={`block w-full rounded-lg border p-3 text-left transition ${candidate.horseId === selectedId ? "border-amber-300 bg-amber-300/10" : "border-stone-800 hover:border-stone-600"}`} key={candidate.id} onClick={() => onSelected(candidate.horseId)} type="button"><p className="font-medium text-stone-100">{displayHorse(candidate.horse)}</p><p className="mt-1 text-sm text-stone-400">#{candidate.horse?.horseNumber} · {sexLabel(candidate.horse?.sex)} · {candidate.horse?.sireLine || "父系未记录"}</p></button>)}{!filtered.length && <p className="p-3 text-sm text-stone-500">没有符合搜索条件的可用候选。</p>}</div></div>;
}

function ReferenceSearch({
  label,
  references,
  selectedId,
  onSelected,
  parent,
  onEdit,
}: {
  label: string;
  references: PedigreeReference[];
  selectedId: string | null;
  onSelected: (id: string | null) => void;
  parent: "sire" | "dam";
  onEdit: (reference: PedigreeReference) => void;
}) {
  const [query, setQuery] = useState("");
  const selected = references.find((reference) => reference.id === selectedId) ?? null;
  const filtered = useMemo(() => {
    const normalized = query.trim().toLocaleLowerCase();
    return references.filter((reference) => {
      const compatible = parent === "sire" ? !reference.sex || reference.sex === "MALE" : !reference.sex || reference.sex === "FEMALE";
      if (!compatible) return false;
      if (!normalized) return true;
      return [reference.name, reference.translatedName, ...reference.aliases].filter(Boolean).join(" ").toLocaleLowerCase().includes(normalized);
    });
  }, [parent, query, references]);
  const missingRequired = selected && (parent === "sire" ? !selected.sireLine : !selected.sireName);

  return <div className="space-y-3"><label className="admin-label">{label}<input className="admin-input" onChange={(event) => setQuery(event.target.value)} placeholder="搜索名称、译名或 aliases" value={query} /></label>{selected && <div className="rounded-lg border border-sky-400/35 bg-sky-400/5 p-4"><div className="flex flex-wrap items-start justify-between gap-3"><div><p className="font-semibold text-sky-100">{selected.name}{selected.translatedName ? ` · ${selected.translatedName}` : ""}</p><p className="mt-1 text-sm text-stone-400">{sexLabel(selected.sex)} · {parent === "sire" ? selected.sireLine || "父系缺失" : selected.sireName || "母父缺失"}</p></div><div className="flex gap-3 text-sm"><button className="text-stone-300 hover:text-red-200" onClick={() => onSelected(null)} type="button">清除</button><button className="text-amber-200 hover:text-amber-100" onClick={() => onEdit(selected)} type="button">编辑资料</button></div></div>{missingRequired && <p className="mt-3 rounded border border-red-400/35 bg-red-400/5 p-3 text-sm leading-6 text-red-100">{parent === "sire" ? "该外部父马资料缺少父系，暂不能用于创建幼驹。请编辑资料或改用手动输入。" : "该外部母马资料缺少母父信息，暂不能用于创建幼驹。请编辑资料或改用手动输入。"}</p>}</div>}<div className="max-h-56 space-y-2 overflow-y-auto rounded-lg border border-stone-800 bg-stone-950/60 p-2">{filtered.map((reference) => { const unavailable = parent === "sire" ? !reference.sireLine : !reference.sireName; return <button className={`block w-full rounded-lg border p-3 text-left transition ${reference.id === selectedId ? "border-amber-300 bg-amber-300/10" : "border-stone-800 hover:border-stone-600"}`} key={reference.id} onClick={() => onSelected(reference.id)} type="button"><p className="font-medium text-stone-100">{reference.name}{reference.translatedName ? <span className="ml-2 text-sm font-normal text-stone-400">{reference.translatedName}</span> : null}</p><p className="mt-1 text-sm text-stone-400">{sexLabel(reference.sex)} · {parent === "sire" ? reference.sireLine || "父系缺失" : reference.sireName || "母父缺失"}{unavailable ? " · 当前不可用于创建" : ""}</p></button>; })}{!filtered.length && <p className="p-3 text-sm text-stone-500">没有可选 active Reference。可直接切换为手动输入。</p>}</div></div>;
}

function FoalCreationPanel({ candidates, references, gameState, onEditReference }: { candidates: BreedingCandidate[]; references: PedigreeReference[]; gameState: GameState; onEditReference: (reference: PedigreeReference) => void }) {
  const router = useRouter();
  const [pending, startTransition] = useTransition();
  const [requestId, setRequestId] = useState(() => crypto.randomUUID());
  const [horseNumber, setHorseNumber] = useState("");
  const [birthYear, setBirthYear] = useState(gameState ? String(gameState.currentWpYear) : "");
  const [foalName, setFoalName] = useState("");
  const [nameKatakana, setNameKatakana] = useState("");
  const [translatedName, setTranslatedName] = useState("");
  const [sex, setSex] = useState("MALE");
  const [coatColor, setCoatColor] = useState("");
  const [sireSource, setSireSource] = useState<FoalParentSource>(candidates.some((candidate) => candidate.candidateType === "STALLION") ? "INTERNAL" : "REFERENCE");
  const [damSource, setDamSource] = useState<FoalParentSource>(candidates.some((candidate) => candidate.candidateType === "BROODMARE") ? "INTERNAL" : "REFERENCE");
  const [sireHorseId, setSireHorseId] = useState<string | null>(null);
  const [damHorseId, setDamHorseId] = useState<string | null>(null);
  const [sireReferenceId, setSireReferenceId] = useState<string | null>(null);
  const [damReferenceId, setDamReferenceId] = useState<string | null>(null);
  const [manualSireName, setManualSireName] = useState("");
  const [manualSireLine, setManualSireLine] = useState("");
  const [manualDamName, setManualDamName] = useState("");
  const [manualBroodmareSireName, setManualBroodmareSireName] = useState("");
  const [message, setMessage] = useState<string | null>(null);
  const [success, setSuccess] = useState<Extract<Awaited<ReturnType<typeof createFoal>>, { ok: true }> | null>(null);

  const stallions = candidates.filter((candidate) => candidate.isActive && candidate.candidateType === "STALLION" && candidate.horse);
  const broodmares = candidates.filter((candidate) => candidate.isActive && candidate.candidateType === "BROODMARE" && candidate.horse);
  const activeReferences = references.filter((reference) => reference.isActive);
  const selectedSireHorse = stallions.find((candidate) => candidate.horseId === sireHorseId)?.horse ?? null;
  const selectedDamHorse = broodmares.find((candidate) => candidate.horseId === damHorseId)?.horse ?? null;
  const selectedSireReference = activeReferences.find((reference) => reference.id === sireReferenceId) ?? null;
  const selectedDamReference = activeReferences.find((reference) => reference.id === damReferenceId) ?? null;

  const restart = () => {
    setRequestId(crypto.randomUUID()); setHorseNumber(""); setBirthYear(gameState ? String(gameState.currentWpYear) : ""); setFoalName(""); setNameKatakana(""); setTranslatedName(""); setSex("MALE"); setCoatColor(""); setSireHorseId(null); setDamHorseId(null); setSireReferenceId(null); setDamReferenceId(null); setManualSireName(""); setManualSireLine(""); setManualDamName(""); setManualBroodmareSireName(""); setMessage(null); setSuccess(null);
  };

  const validate = () => {
    if (!horseNumber || !birthYear || !foalName.trim() || !coatColor.trim()) return "请完整填写马号、WP 出生年份、幼驹阶段名、性别与毛色。";
    if (sireSource === "INTERNAL" && !sireHorseId) return "请选择内部候选种牡马，或改用外部资料/手动输入。";
    if (damSource === "INTERNAL" && !damHorseId) return "请选择内部候选繁殖牝马，或改用外部资料/手动输入。";
    if (sireSource === "REFERENCE" && (!selectedSireReference || !selectedSireReference.sireLine)) return "请选择包含父系的外部父马资料，或改用手动输入。";
    if (damSource === "REFERENCE" && (!selectedDamReference || !selectedDamReference.sireName)) return "请选择包含母父信息的外部母马资料，或改用手动输入。";
    if (sireSource === "MANUAL" && (!manualSireName.trim() || !manualSireLine.trim())) return "手动父马必须填写父马名与父系。";
    if (damSource === "MANUAL" && (!manualDamName.trim() || !manualBroodmareSireName.trim())) return "手动母马必须填写母马名与母父名。";
    return null;
  };

  const submit = () => {
    const validation = validate();
    if (validation) { setMessage(validation); return; }
    setMessage(null);
    const input: CreateFoalInput = { requestId, horseNumber, birthYear, foalName, nameKatakana, translatedName, sex, coatColor, sireSourceType: sireSource, sireHorseId, sireReferenceId, manualSireName, manualSireLine, damSourceType: damSource, damHorseId, damReferenceId, manualDamName, manualBroodmareSireName };
    startTransition(async () => {
      const result = await createFoal(input);
      if (!result.ok) { setMessage(result.message); return; }
      setSuccess(result);
      router.refresh();
    });
  };

  if (success) {
    const horse = success.horse;
    return <section className="rounded-xl border border-emerald-400/40 bg-emerald-400/5 p-6"><p className="text-sm font-semibold tracking-[0.18em] text-emerald-200">幼驹已创建</p><h2 className="mt-2 text-2xl font-semibold text-stone-100">幼驹创建成功</h2><p className="mt-3 text-sm text-emerald-100">{success.notice}</p><div className="mt-6 grid gap-3 sm:grid-cols-2"><div className="rounded-lg border border-stone-800 bg-stone-950/60 p-4"><p className="text-xs text-stone-500">马匹</p><p className="mt-2 font-semibold text-stone-100">#{horse.horseNumber} · {horse.translatedName || horse.foalName}</p><p className="mt-1 text-sm text-stone-400">{sexLabel(horse.sex)} · {horse.coatColor} · 幼驹 / 无马主</p></div><div className="rounded-lg border border-stone-800 bg-stone-950/60 p-4"><p className="text-xs text-stone-500">血统快照</p><p className="mt-2 text-sm text-stone-100">父：{horse.sireName} · {horse.sireLine}</p><p className="mt-1 text-sm text-stone-100">母：{horse.damName || "—"} · 母父：{horse.broodmareSireName}</p></div></div><div className="mt-6 flex flex-wrap gap-3"><Link className="admin-button" href={`/admin/horses/${horse.id}`}>查看马匹</Link><button className="inline-flex items-center justify-center rounded-lg border border-stone-600 px-4 py-2.5 text-sm font-semibold text-stone-200 hover:border-amber-300" onClick={restart} type="button">继续新建幼驹</button><Link className="inline-flex items-center justify-center rounded-lg border border-stone-600 px-4 py-2.5 text-sm font-semibold text-stone-200 hover:border-amber-300" href="/admin/breeding">返回繁育管理</Link></div></section>;
  }

  return <section className="space-y-7"><div className="rounded-xl border border-stone-800 bg-stone-900 p-5 sm:p-6"><p className="text-sm font-semibold tracking-[0.18em] text-amber-300">GM · 幼驹录入</p><h2 className="mt-2 text-2xl font-semibold text-stone-100">录入 WP 已出生幼驹</h2><p className="mt-3 max-w-3xl text-sm leading-6 text-stone-400">这不是配种或生产模拟。仅在 Winning Post 已确认出生后，将幼驹录入 HorseRPG；数据库会在提交时再次决定并冻结血统快照。</p>{!gameState && <p className="mt-4 rounded-lg border border-amber-300/30 bg-amber-300/5 p-3 text-sm text-amber-100">游戏时间尚未初始化，请手动确认 WP 出生年份。</p>}</div><div className="grid gap-6 xl:grid-cols-[minmax(0,0.9fr)_minmax(0,1.1fr)]"><section className="rounded-xl border border-stone-800 bg-stone-900 p-5 sm:p-6"><h3 className="text-lg font-semibold text-amber-200">幼驹基础信息</h3><div className="mt-5 grid gap-4 sm:grid-cols-2"><label className="admin-label">马号 *<input className="admin-input" inputMode="numeric" min="1" onChange={(event) => setHorseNumber(event.target.value)} required value={horseNumber} /></label><label className="admin-label">WP 出生年份 *<input className="admin-input" inputMode="numeric" min="1" onChange={(event) => setBirthYear(event.target.value)} required value={birthYear} /></label><label className="admin-label sm:col-span-2">幼驹阶段名 *<input className="admin-input" onChange={(event) => setFoalName(event.target.value)} required value={foalName} /></label><label className="admin-label">正式片假名名（可空）<input className="admin-input" onChange={(event) => setNameKatakana(event.target.value)} value={nameKatakana} /></label><label className="admin-label">译名（可空）<input className="admin-input" onChange={(event) => setTranslatedName(event.target.value)} value={translatedName} /></label><label className="admin-label">性别 *<select className="admin-input" onChange={(event) => setSex(event.target.value)} value={sex}><option value="MALE">牡</option><option value="FEMALE">牝</option><option value="GELDING">阉</option></select></label><label className="admin-label">毛色 *<input className="admin-input" onChange={(event) => setCoatColor(event.target.value)} required value={coatColor} /></label></div></section><section className="rounded-xl border border-stone-800 bg-stone-900 p-5 sm:p-6"><h3 className="text-lg font-semibold text-amber-200">创建前预览</h3><div className="mt-5 space-y-4 rounded-lg border border-stone-800 bg-stone-950/60 p-4"><div><p className="text-xs text-stone-500">即将创建</p><p className="mt-1 font-semibold text-stone-100">马匹 #{horseNumber || "—"} · {birthYear || "—"} 年出生 · {coatColor || "—"} · {sexLabel(sex)}</p><p className="mt-1 text-sm text-stone-400">{translatedName || nameKatakana || foalName || "尚未填写名称"}</p></div><div className="border-t border-stone-800 pt-4"><div className="flex flex-wrap items-center gap-2"><p className="text-sm font-semibold text-stone-200">父：{sireSource === "INTERNAL" ? displayHorse(selectedSireHorse) : sireSource === "REFERENCE" ? selectedSireReference?.name || "尚未选择" : manualSireName || "尚未填写"}</p>{sourceBadge(sireSource)}</div><p className="mt-1 text-sm text-stone-400">父系：{sireSource === "INTERNAL" ? selectedSireHorse?.sireLine || "—" : sireSource === "REFERENCE" ? selectedSireReference?.sireLine || "缺失" : manualSireLine || "—"}</p></div><div className="border-t border-stone-800 pt-4"><div className="flex flex-wrap items-center gap-2"><p className="text-sm font-semibold text-stone-200">母：{damSource === "INTERNAL" ? displayHorse(selectedDamHorse) : damSource === "REFERENCE" ? selectedDamReference?.name || "尚未选择" : manualDamName || "尚未填写"}</p>{sourceBadge(damSource)}</div><p className="mt-1 text-sm text-stone-400">母父：{damSource === "INTERNAL" ? "由数据库根据母马记录生成快照" : damSource === "REFERENCE" ? selectedDamReference?.sireName || "缺失" : manualBroodmareSireName || "—"}</p></div><p className="border-t border-stone-800 pt-4 text-sm text-emerald-100">创建后：幼驹 / 无马主。不会自动加入庭先或拍卖，也不会自动创建血统因子。</p></div></section></div><section className="grid gap-6 xl:grid-cols-2"><section className="rounded-xl border border-stone-800 bg-stone-900 p-5 sm:p-6"><div className="flex flex-wrap items-center gap-3"><h3 className="text-lg font-semibold text-amber-200">父马来源</h3>{sourceBadge(sireSource)}</div><p className="mt-2 text-sm text-stone-400">父马与母马可分别选择任意来源，不会被绑定为同一种。</p><div className="mt-4"><ParentSourceSwitch parent="sire" setSource={setSireSource} source={sireSource} /></div><div className="mt-5">{sireSource === "INTERNAL" ? <>{stallions.length ? <CandidateSearch candidates={stallions} label="内部候选种牡马" onSelected={setSireHorseId} selectedId={sireHorseId} /> : <p className="rounded-lg border border-stone-800 bg-stone-950/60 p-4 text-sm text-stone-500">暂无候选种牡马。可选择外部资料或手动填写。</p>}</> : sireSource === "REFERENCE" ? <ReferenceSearch label="外部父马资料" onEdit={onEditReference} onSelected={setSireReferenceId} parent="sire" references={activeReferences} selectedId={sireReferenceId} /> : <div className="grid gap-4"><label className="admin-label">父马名 *<input className="admin-input" onChange={(event) => setManualSireName(event.target.value)} value={manualSireName} /></label><label className="admin-label">父系 *<input className="admin-input" onChange={(event) => setManualSireLine(event.target.value)} placeholder="例如：Halo系" value={manualSireLine} /></label></div>}</div></section><section className="rounded-xl border border-stone-800 bg-stone-900 p-5 sm:p-6"><div className="flex flex-wrap items-center gap-3"><h3 className="text-lg font-semibold text-amber-200">母马来源</h3>{sourceBadge(damSource)}</div><p className="mt-2 text-sm text-stone-400">内部母马选择后，母父由数据库根据该马匹的记录生成快照。</p><div className="mt-4"><ParentSourceSwitch parent="dam" setSource={setDamSource} source={damSource} /></div><div className="mt-5">{damSource === "INTERNAL" ? <>{broodmares.length ? <CandidateSearch candidates={broodmares} label="内部候选繁殖牝马" onSelected={setDamHorseId} selectedId={damHorseId} /> : <p className="rounded-lg border border-stone-800 bg-stone-950/60 p-4 text-sm text-stone-500">暂无候选繁殖牝马。可选择外部资料或手动填写。</p>}</> : damSource === "REFERENCE" ? <ReferenceSearch label="外部母马资料" onEdit={onEditReference} onSelected={setDamReferenceId} parent="dam" references={activeReferences} selectedId={damReferenceId} /> : <div className="grid gap-4"><label className="admin-label">母马名 *<input className="admin-input" onChange={(event) => setManualDamName(event.target.value)} value={manualDamName} /></label><label className="admin-label">母父名 *<input className="admin-input" onChange={(event) => setManualBroodmareSireName(event.target.value)} value={manualBroodmareSireName} /></label></div>}</div></section></section><section className="rounded-xl border border-amber-300/35 bg-amber-300/5 p-5 sm:p-6"><div className="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between"><div><h3 className="text-lg font-semibold text-amber-100">确认录入</h3><p className="mt-2 text-sm leading-6 text-stone-300">此表单打开时会生成一次性请求标识；网络重试将保留同一标识，以便数据库安全地返回原马匹，而不会重复创建。</p></div><button className="admin-button" disabled={pending} onClick={submit} type="button">{pending ? "正在创建幼驹…" : "创建幼驹"}</button></div>{message && <div aria-live="polite" className="mt-4 rounded-lg border border-red-400/35 bg-red-400/5 p-4 text-sm leading-6 text-red-100"><p>{message}</p>{message.includes("重新开始") && <button className="mt-3 rounded-md border border-red-300/60 px-3 py-2 font-semibold hover:bg-red-300/10" onClick={restart} type="button">重新开始新建流程</button>}</div>}</section></section>;
}

export function BreedingWorkbench({ candidates, references, gameState, initialTab }: BreedingWorkbenchProps) {
  const [tab, setTab] = useState<Tab>(initialTab === "references" || initialTab === "foals" ? initialTab : "candidates");
  const [referenceEditor, setReferenceEditor] = useState<PedigreeReferenceInput | null>(null);
  const [referenceSearch, setReferenceSearch] = useState("");
  const [showHistory, setShowHistory] = useState(false);
  const [notice, setNotice] = useState<string | null>(null);
  const [deactivateReference, setDeactivateReference] = useState<PedigreeReference | null>(null);
  const [deactivationReason, setDeactivationReason] = useState("");
  const [pending, startTransition] = useTransition();
  const router = useRouter();

  const activeCandidates = candidates.filter((candidate) => candidate.isActive && candidate.horse);
  const inactiveCandidates = candidates.filter((candidate) => !candidate.isActive && candidate.horse);
  const stallions = activeCandidates.filter((candidate) => candidate.candidateType === "STALLION");
  const broodmares = activeCandidates.filter((candidate) => candidate.candidateType === "BROODMARE");
  const filteredReferences = references.filter((reference) => [reference.name, reference.translatedName, ...reference.aliases].filter(Boolean).join(" ").toLocaleLowerCase().includes(referenceSearch.trim().toLocaleLowerCase()));

  const confirmDeactivateReference = () => {
    if (!deactivateReference) return;
    startTransition(async () => {
      const result = await deactivatePedigreeReference(deactivateReference.id, deactivationReason);
      if (!result.ok) { setNotice(result.message); return; }
      setNotice(result.notice); setDeactivateReference(null); setDeactivationReason(""); router.refresh();
    });
  };

  const openReferenceEditor = (reference?: PedigreeReference) => {
    setTab("references");
    setReferenceEditor(reference ? referenceInput(reference) : emptyReference());
  };

  const tabs: Array<[Tab, string, string]> = [["candidates", "繁育候选", `${activeCandidates.length} active`], ["references", "外部血统资料", `${references.filter((reference) => reference.isActive).length} active`], ["foals", "新建幼驹", "WP 已出生录入"]];

  return <main className="mx-auto w-full max-w-7xl px-4 py-8 sm:px-6 sm:py-10"><section className="border-b border-stone-800 pb-7"><p className="text-sm font-semibold tracking-[0.24em] text-amber-300">GM · 繁育管理</p><div className="mt-3 flex flex-col gap-4 lg:flex-row lg:items-end lg:justify-between"><div><h1 className="text-3xl font-semibold tracking-tight">繁育候选与幼驹录入</h1><p className="mt-3 max-w-3xl text-sm leading-6 text-stone-400">管理内部繁育候选、外部血统输入资料，并录入 Winning Post 已确认出生的幼驹。这里不模拟配种、受胎或自动生产。</p></div><button className="admin-button w-fit" onClick={() => { setTab("foals"); setReferenceEditor(null); }} type="button">新建幼驹</button></div></section>{notice && <p aria-live="polite" className="mt-5 rounded-xl border border-amber-300/35 bg-amber-300/5 p-4 text-sm leading-6 text-amber-100">{notice}</p>}<nav aria-label="繁育功能" className="mt-6 flex overflow-x-auto border-b border-stone-800">{tabs.map(([value, label, hint]) => <button className={`shrink-0 border-b-2 px-4 py-3 text-left text-sm ${tab === value ? "border-amber-300 text-amber-100" : "border-transparent text-stone-400 hover:text-stone-200"}`} key={value} onClick={() => { setTab(value); setReferenceEditor(null); }} type="button"><span className="block font-semibold">{label}</span><span className="mt-1 block text-xs text-stone-500">{hint}</span></button>)}</nav>{tab === "candidates" && <section className="mt-7 space-y-8"><div className="grid gap-6 lg:grid-cols-2"><CandidateColumn candidates={stallions} empty="暂无候选种牡马。请在已退役牡马 详情中加入候选。" title="候选种牡马" /><CandidateColumn candidates={broodmares} empty="暂无候选繁殖牝马。请在已退役牝马 详情中加入候选。" title="候选繁殖牝马" /></div><section className="rounded-xl border border-stone-800 bg-stone-900 p-5 sm:p-6"><div className="flex flex-wrap items-center justify-between gap-4"><div><h2 className="text-xl font-semibold text-amber-200">历史 / 已停用</h2><p className="mt-2 text-sm text-stone-400">已停用候选不会出现在新建幼驹选择器中；重新启用仍须由马匹详情中的受控操作完成。</p></div><button className="rounded-lg border border-stone-600 px-4 py-2.5 text-sm font-semibold text-stone-200 hover:border-amber-300" onClick={() => setShowHistory((current) => !current)} type="button">{showHistory ? "收起历史" : `查看历史（${inactiveCandidates.length}）`}</button></div>{showHistory && <div className="mt-5 grid gap-4 md:grid-cols-2">{inactiveCandidates.map((candidate) => <CandidateCard candidate={candidate} key={candidate.id} />)}{!inactiveCandidates.length && <p className="text-sm text-stone-500">暂无已停用候选。</p>}</div>}</section></section>}{tab === "references" && <section className="mt-7 space-y-6">{referenceEditor ? <ReferenceEditor initial={referenceEditor} onClose={() => setReferenceEditor(null)} onSaved={(message) => { setNotice(message); setReferenceEditor(null); }} /> : <div className="flex flex-col gap-4 rounded-xl border border-stone-800 bg-stone-900 p-5 sm:flex-row sm:items-end sm:justify-between sm:p-6"><div><h2 className="text-xl font-semibold text-amber-200">外部血统资料库</h2><p className="mt-2 text-sm leading-6 text-stone-400">可记录不完整的资料；新建幼驹时，页面会提前提示缺少父系或母父的资料不可作为对应父母。</p></div><button className="admin-button w-fit" onClick={() => openReferenceEditor()} type="button">新增外部血统资料</button></div>}<label className="admin-label">搜索资料库<input className="admin-input" onChange={(event) => setReferenceSearch(event.target.value)} placeholder="搜索标准名称、译名或别名" value={referenceSearch} /></label><div className="grid gap-4 md:grid-cols-2 xl:grid-cols-3">{filteredReferences.map((reference) => <article className={`rounded-xl border p-5 ${reference.isActive ? "border-stone-800 bg-stone-900" : "border-stone-800/70 bg-stone-950/50"}`} key={reference.id}><div className="flex flex-wrap items-start justify-between gap-3"><div><h3 className="font-semibold text-stone-100">{reference.name}</h3>{reference.translatedName && <p className="mt-1 text-sm text-stone-400">{reference.translatedName}</p>}</div><span className={`rounded-full border px-2.5 py-1 text-xs font-semibold ${reference.isActive ? "border-emerald-400/40 text-emerald-100" : "border-stone-700 text-stone-400"}`}>{reference.isActive ? "使用中" : "已停用"}</span></div><dl className="mt-5 grid gap-3 text-sm"><div><dt className="text-xs text-stone-500">性别 / 父系</dt><dd className="mt-1 text-stone-200">{sexLabel(reference.sex)} · {reference.sireLine || "—"}</dd></div><div><dt className="text-xs text-stone-500">父马 / 母马 / 母父</dt><dd className="mt-1 text-stone-200">{reference.sireName || "—"} / {reference.damName || "—"} / {reference.broodmareSireName || "—"}</dd></div>{reference.aliases.length > 0 && <div className="flex flex-wrap gap-1.5">{reference.aliases.map((alias) => <span className="rounded-full border border-stone-700 px-2 py-1 text-xs text-stone-300" key={alias}>{alias}</span>)}</div>}{reference.notes && <div><dt className="text-xs text-stone-500">GM 备注</dt><dd className="mt-1 whitespace-pre-wrap text-stone-400">{reference.notes}</dd></div>}</dl><div className="mt-5 flex flex-wrap gap-3"><button className="text-sm font-semibold text-amber-200 hover:text-amber-100" onClick={() => openReferenceEditor(reference)} type="button">编辑</button>{reference.isActive && <button className="text-sm font-semibold text-red-300 hover:text-red-200" onClick={() => setDeactivateReference(reference)} type="button">停用</button>}</div></article>)}{!filteredReferences.length && <p className="rounded-xl border border-stone-800 bg-stone-900 p-6 text-sm text-stone-500 md:col-span-2 xl:col-span-3">尚未建立外部血统资料，可直接手动填写血统。</p>}</div>{deactivateReference && <section className="rounded-xl border border-red-400/40 bg-red-400/5 p-5"><h3 className="font-semibold text-red-100">停用「{deactivateReference.name}」？</h3><p className="mt-2 text-sm leading-6 text-stone-300">停用后将不会出现在新建幼驹的默认血统选择中；已有马匹血统不受影响。</p><label className="admin-label mt-4">停用原因（可选）<textarea className="admin-input min-h-20" onChange={(event) => setDeactivationReason(event.target.value)} value={deactivationReason} /></label><div className="mt-4 flex flex-wrap gap-3"><button className="inline-flex items-center justify-center rounded-lg border border-red-400/60 px-4 py-2.5 text-sm font-semibold text-red-200 hover:bg-red-400/10 disabled:opacity-60" disabled={pending} onClick={confirmDeactivateReference} type="button">{pending ? "停用中…" : "确认停用"}</button><button className="inline-flex items-center justify-center rounded-lg border border-stone-600 px-4 py-2.5 text-sm font-semibold text-stone-200 hover:border-amber-300" disabled={pending} onClick={() => setDeactivateReference(null)} type="button">取消</button></div></section>}</section>}{tab === "foals" && <section className="mt-7"><FoalCreationPanel candidates={candidates} gameState={gameState} onEditReference={(reference) => { setTab("references"); setReferenceEditor(referenceInput(reference)); }} references={references} /></section>}</main>;
}

function CandidateColumn({ candidates, empty, title }: { candidates: BreedingCandidate[]; empty: string; title: string }) {
  return <section className="rounded-xl border border-stone-800 bg-stone-900 p-5 sm:p-6"><div className="flex items-center justify-between gap-4"><h2 className="text-xl font-semibold text-amber-200">{title}</h2><span className="font-mono text-sm text-stone-500">{candidates.length}</span></div><div className="mt-5 space-y-4">{candidates.map((candidate) => <CandidateCard candidate={candidate} key={candidate.id} />)}{!candidates.length && <p className="rounded-lg border border-stone-800 bg-stone-950/60 p-4 text-sm leading-6 text-stone-500">{empty}</p>}</div></section>;
}

function CandidateCard({ candidate }: { candidate: BreedingCandidate }) {
  const horse = candidate.horse;
  if (!horse) return null;
  return <article className="rounded-lg border border-stone-800 bg-stone-950/60 p-4"><div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between"><div><Link className="font-semibold text-stone-100 hover:text-amber-100" href={`/admin/horses/${horse.id}`}>{displayHorse(horse)}</Link><p className="mt-1 text-sm text-stone-400">#{horse.horseNumber} · {sexLabel(horse.sex)} · {horse.birthYear} 年生 · {formatHorseLifeStage(horse.lifeStage)}</p></div><span className={`w-fit rounded-full border px-2.5 py-1 text-xs font-semibold ${candidate.isActive ? "border-emerald-400/40 text-emerald-100" : "border-stone-700 text-stone-400"}`}>{candidate.candidateType === "STALLION" ? "种牡马" : "繁殖牝马"} · {candidate.isActive ? "使用中" : "已停用"}</span></div>{candidate.notes && <p className="mt-3 text-sm leading-6 text-stone-400">备注：{candidate.notes}</p>}{candidate.isActive && <BreedingCandidateControls candidate={{ candidateType: candidate.candidateType, isActive: true, notes: candidate.notes }} compact horseId={horse.id} lifeStage={horse.lifeStage} sex={horse.sex} />}</article>;
}
