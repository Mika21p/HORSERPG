"use client";

import { useMemo, useState } from "react";

import { ActionForm } from "@/components/action-form";
import { formatRaceGrade, formatRaceKind } from "@/lib/format";

type ServerAction = (formData: FormData) => void | Promise<void>;

export type ActualRaceCatalogOption = {
  id: string;
  name: string;
  grade: string;
  default_wp_month: number;
  default_wp_week: number;
  is_active: boolean;
};

type ActualRaceFormProps = {
  action: ServerAction;
  catalogs: ActualRaceCatalogOption[];
  currentWp: { year: number; month: number; week: number };
  defaultValues?: {
    wpYear?: number;
    wpMonth?: number;
    wpWeek?: number;
    raceKind?: string;
    raceCatalogId?: string | null;
    raceLabel?: string | null;
  };
  includeReason?: boolean;
  submitLabel: string;
  pendingLabel: string;
  confirmation?: string;
};

export function ActualRaceForm({
  action,
  catalogs,
  currentWp,
  defaultValues,
  includeReason = false,
  submitLabel,
  pendingLabel,
  confirmation,
}: ActualRaceFormProps) {
  const [kind, setKind] = useState(defaultValues?.raceKind ?? "CATALOG");
  const [catalogId, setCatalogId] = useState(defaultValues?.raceCatalogId ?? "");
  const selectedCatalog = useMemo(() => catalogs.find((catalog) => catalog.id === catalogId), [catalogId, catalogs]);

  return (
    <ActionForm action={action} className="space-y-4" confirmation={confirmation} pendingLabel={pendingLabel} submitLabel={submitLabel}>
      <div className="grid gap-4 sm:grid-cols-[minmax(0,1fr)_minmax(8rem,0.7fr)_minmax(8rem,0.7fr)]">
        <label className="admin-label">WP 年
          <input className="admin-input" defaultValue={defaultValues?.wpYear ?? currentWp.year} max={currentWp.year} min="1" name="wp_year" required type="number" />
        </label>
        <label className="admin-label">月
          <select className="admin-input" defaultValue={defaultValues?.wpMonth ?? currentWp.month} name="wp_month">
            {Array.from({ length: 12 }, (_, index) => index + 1).map((month) => <option key={month} value={month}>{month} 月</option>)}
          </select>
        </label>
        <label className="admin-label">周次
          <select className="admin-input" defaultValue={defaultValues?.wpWeek ?? currentWp.week} name="wp_week">
            {Array.from({ length: 5 }, (_, index) => index + 1).map((week) => <option key={week} value={week}>第 {week} 周</option>)}
          </select>
        </label>
      </div>
      <p className="-mt-2 text-xs leading-5 text-stone-500">默认当前 WP 周。请录入当前周或已经发生的历史周；数据库会拒绝未来实际比赛。</p>

      <label className="admin-label">比赛类型
        <select className="admin-input" name="race_kind" onChange={(event) => setKind(event.target.value)} value={kind}>
          <option value="CATALOG">固定比赛</option>
          <option value="MAIDEN">未胜利赛</option>
          <option value="CONDITION">条件赛</option>
          <option value="OTHER">其他比赛</option>
        </select>
      </label>

      {kind === "CATALOG" ? (
        <div>
          <label className="admin-label">比赛目录
            <select className="admin-input" name="race_catalog_id" onChange={(event) => setCatalogId(event.target.value)} required value={catalogId}>
              <option value="">选择固定比赛</option>
              {catalogs.map((catalog) => <option key={catalog.id} value={catalog.id}>{catalog.name} · {formatRaceGrade(catalog.grade)}{catalog.is_active ? "" : " · 已停用 / 历史比赛可用"}</option>)}
            </select>
          </label>
          {selectedCatalog && <p className="mt-2 rounded-lg border border-stone-800 bg-stone-950/60 p-3 text-xs leading-5 text-stone-400">目录建议时间：{selectedCatalog.default_wp_month} 月第 {selectedCatalog.default_wp_week} 周 · 实际比赛时间由 GM 明确填写，不会强制使用建议时间。{!selectedCatalog.is_active && " 该目录已停用，但可用于历史比赛补录。"}</p>}
        </div>
      ) : (
        <label className="admin-label">实际比赛名称 / 说明
          <input className="admin-input" defaultValue={defaultValues?.raceLabel ?? ""} name="race_label" placeholder={kind === "MAIDEN" ? "例如：3岁未胜利" : kind === "CONDITION" ? "例如：1胜级" : "例如：地方交流赛"} required />
        </label>
      )}

      {includeReason && <label className="admin-label">纠错原因
        <textarea className="admin-input min-h-24" name="reason" placeholder="说明为什么需要修正实际比赛事实" required />
      </label>}

      <p className="text-xs text-stone-500">当前选择：{formatRaceKind(kind)}。目录中的名称与分级会在创建或纠错时作为实际比赛历史快照保存。</p>
    </ActionForm>
  );
}
