"use client";

import { useMemo, useState } from "react";

import { ActionForm } from "@/components/action-form";
import { formatHorseLifeStage, formatWpTime } from "@/lib/format";

type ServerAction = (formData: FormData) => void | Promise<void>;

export type RaceCatalogOption = {
  id: string;
  name: string;
  grade: string;
  default_wp_month: number;
  default_wp_week: number;
};

export type RaceInjuryOption = {
  wp_start_year: number;
  wp_start_month: number;
  wp_start_week: number;
  wp_end_year: number;
  wp_end_month: number;
  wp_end_week: number;
};

export type RaceHorseOption = {
  id: string;
  horse_number: number | string;
  foal_name: string;
  translated_name: string | null;
  owner_id: string | null;
  life_stage: string;
  current_jockey_name: string | null;
  injuries?: RaceInjuryOption[];
};

export type RaceScheduleValues = {
  wpYear: number;
  wpMonth: number;
  wpWeek: number;
  raceKind: string;
  raceCatalogId?: string | null;
  raceLabel?: string | null;
  jockey?: string | null;
  runningStyle?: string | null;
  note?: string | null;
  horseId?: string | null;
};

type RaceScheduleFormProps = {
  action: ServerAction;
  catalogs: RaceCatalogOption[];
  confirmation?: string;
  defaultValues: RaceScheduleValues;
  horses?: RaceHorseOption[];
  mode: "PLAYER_REQUEST" | "GM_CONFIRM" | "GM_DIRECT";
  pendingLabel: string;
  submitLabel: string;
};

const raceKinds = [
  ["CATALOG", "固定比赛"],
  ["MAIDEN", "未胜利赛"],
  ["CONDITION", "条件赛"],
  ["OTHER", "其他比赛"],
] as const;

const runningStyles = ["", "逃", "先", "差", "追"] as const;

function horseDisplayName(horse: RaceHorseOption) {
  return horse.translated_name || horse.foal_name;
}

export function RaceScheduleForm({
  action,
  catalogs,
  confirmation,
  defaultValues,
  horses = [],
  mode,
  pendingLabel,
  submitLabel,
}: RaceScheduleFormProps) {
  const [horseId, setHorseId] = useState(defaultValues.horseId ?? "");
  const [wpYear, setWpYear] = useState(String(defaultValues.wpYear));
  const [wpMonth, setWpMonth] = useState(String(defaultValues.wpMonth));
  const [wpWeek, setWpWeek] = useState(String(defaultValues.wpWeek));
  const [raceKind, setRaceKind] = useState(defaultValues.raceKind || "CATALOG");
  const [catalogId, setCatalogId] = useState(defaultValues.raceCatalogId ?? "");
  const [jockey, setJockey] = useState(defaultValues.jockey ?? "");

  const selectedHorse = useMemo(
    () => horses.find((horse) => horse.id === horseId) ?? null,
    [horseId, horses],
  );
  const isDirect = mode === "GM_DIRECT";
  const isPlayer = mode === "PLAYER_REQUEST";
  const noteLabel = isPlayer ? "玩家备注（可选）" : "GM 备注（可选）";
  const catalogSelected = raceKind === "CATALOG";

  function applyCatalogDefaults(nextCatalogId: string) {
    setCatalogId(nextCatalogId);
    const catalog = catalogs.find((item) => item.id === nextCatalogId);
    if (catalog) {
      setWpMonth(String(catalog.default_wp_month));
      setWpWeek(String(catalog.default_wp_week));
    }
  }

  function selectHorse(nextHorseId: string) {
    setHorseId(nextHorseId);
    const horse = horses.find((item) => item.id === nextHorseId);
    setJockey(horse?.current_jockey_name ?? "");
  }

  return (
    <ActionForm
      action={action}
      className="space-y-4"
      confirmation={confirmation}
      pendingLabel={pendingLabel}
      submitLabel={submitLabel}
    >
      {mode !== "GM_CONFIRM" && (
        <label className="admin-label">
          马匹
          <select className="admin-input" name="horse_id" onChange={(event) => selectHorse(event.target.value)} required value={horseId}>
            <option value="">选择马匹</option>
            {horses.map((horse) => {
              const unavailable = horse.life_stage !== "ACTIVE" || (isDirect && !horse.owner_id);
              const explanation = horse.life_stage !== "ACTIVE"
                ? `非现役（${formatHorseLifeStage(horse.life_stage)}）`
                : !horse.owner_id
                  ? "未归属"
                  : "";
              return (
                <option disabled={unavailable} key={horse.id} value={horse.id}>
                  #{horse.horse_number} · {horseDisplayName(horse)}{explanation ? ` · ${explanation}` : ""}
                </option>
              );
            })}
          </select>
        </label>
      )}

      {mode !== "GM_CONFIRM" && !horses.some((horse) => horse.life_stage === "ACTIVE" && (!isDirect || horse.owner_id)) && (
        <p className="rounded-lg border border-amber-300/30 bg-amber-300/5 p-3 text-sm leading-6 text-amber-100">
          当前没有可安排的现役马匹。
        </p>
      )}

      {selectedHorse?.injuries?.length ? (
        <section className="rounded-lg border border-red-400/35 bg-red-400/5 p-4 text-sm leading-6 text-red-100">
          <p className="font-semibold">当前有效伤病提醒</p>
          {selectedHorse.injuries.map((injury, index) => (
            <p className="mt-2" key={`${injury.wp_start_year}-${injury.wp_start_month}-${injury.wp_start_week}-${index}`}>
              伤病：{formatWpTime(injury.wp_start_year, injury.wp_start_month, injury.wp_start_week)} 至 {formatWpTime(injury.wp_end_year, injury.wp_end_month, injury.wp_end_week)}。结束周仍不可参赛，从下一 WP 周开始可报名。
            </p>
          ))}
          <p className="mt-2 text-red-200/80">页面仅作提示，数据库会在提交最终赛程时再次裁定。</p>
        </section>
      ) : null}

      <div className="grid gap-4 sm:grid-cols-3">
        <label className="admin-label">WP 年份<input className="admin-input" min="1" name="wp_year" onChange={(event) => setWpYear(event.target.value)} required step="1" type="number" value={wpYear} /></label>
        <label className="admin-label">月份<select className="admin-input" name="wp_month" onChange={(event) => setWpMonth(event.target.value)} value={wpMonth}>{Array.from({ length: 12 }, (_, index) => index + 1).map((month) => <option key={month} value={month}>{month} 月</option>)}</select></label>
        <label className="admin-label">周次<select className="admin-input" name="wp_week" onChange={(event) => setWpWeek(event.target.value)} value={wpWeek}>{Array.from({ length: 5 }, (_, index) => index + 1).map((week) => <option key={week} value={week}>第 {week} 周</option>)}</select></label>
      </div>

      <label className="admin-label">
        比赛类型
        <select className="admin-input" name="race_kind" onChange={(event) => setRaceKind(event.target.value)} value={raceKind}>
          {raceKinds.map(([value, label]) => <option key={value} value={value}>{label}</option>)}
        </select>
      </label>

      {catalogSelected ? (
        <label className="admin-label">
          固定比赛
          <select className="admin-input" name="race_catalog_id" onChange={(event) => applyCatalogDefaults(event.target.value)} required value={catalogId}>
            <option value="">选择可用固定比赛</option>
            {catalogs.map((catalog) => <option key={catalog.id} value={catalog.id}>{catalog.name} · {catalog.grade} · 默认 {catalog.default_wp_month} 月第 {catalog.default_wp_week} 周</option>)}
          </select>
          {!catalogs.length && <span className="mt-2 block text-xs text-amber-200">暂无可用固定比赛，请联系 GM。</span>}
          <input name="race_label" type="hidden" value="" />
        </label>
      ) : (
        <label className="admin-label">
          比赛名称 / 说明
          <input className="admin-input" defaultValue={defaultValues.raceLabel ?? ""} name="race_label" placeholder="例如：3岁未胜利、1胜级、地方交流赛" required />
          <input name="race_catalog_id" type="hidden" value="" />
        </label>
      )}

      <p className="-mt-2 text-xs leading-5 text-stone-500">固定比赛的默认月 / 周只用于辅助填充；最终仍可手动调整。</p>

      <div className="grid gap-4 sm:grid-cols-2">
        <label className="admin-label">{isPlayer ? "希望骑手（可选）" : "最终骑手（可选）"}<input className="admin-input" name="jockey" onChange={(event) => setJockey(event.target.value)} placeholder="可留空" value={jockey} /></label>
        <label className="admin-label">{isPlayer ? "希望跑法（可选）" : "最终跑法（可选）"}<select className="admin-input" defaultValue={defaultValues.runningStyle ?? ""} name="running_style">{runningStyles.map((style) => <option key={style || "unspecified"} value={style}>{style || "未指定"}</option>)}</select></label>
      </div>

      <label className="admin-label">{noteLabel}<textarea className="admin-input min-h-24" defaultValue={defaultValues.note ?? ""} name="note" placeholder={isPlayer ? "例如：优先这场，没有就改下周" : "只供 GM 内部参考，不向玩家公开"} /></label>
    </ActionForm>
  );
}
