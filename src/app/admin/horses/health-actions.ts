"use server";

import { revalidatePath } from "next/cache";

import { requireGM } from "@/lib/auth/session";

export type HealthActionResult = { ok: boolean; message: string };

export type InjuryFacts = {
  startYear: number;
  startMonth: number;
  startWeek: number;
  endYear: number;
  endMonth: number;
  endWeek: number;
  notes: string;
};

function optionalText(value: string | null | undefined) {
  const normalized = value?.trim() ?? "";
  return normalized || null;
}

function validWpPart(value: number, minimum: number, maximum?: number) {
  return Number.isInteger(value) && value >= minimum && (maximum === undefined || value <= maximum);
}

function validInjuryFacts(facts: InjuryFacts | null | undefined) {
  if (!facts) return true;
  return validWpPart(facts.startYear, 1)
    && validWpPart(facts.startMonth, 1, 12)
    && validWpPart(facts.startWeek, 1, 5)
    && validWpPart(facts.endYear, 1)
    && validWpPart(facts.endMonth, 1, 12)
    && validWpPart(facts.endWeek, 1, 5);
}

function healthError(error: { code?: string; message?: string } | null, fallback: string) {
  const message = error?.message?.toLowerCase() ?? "";
  if (error?.code === "42501" || message.includes("only a gm")) return "当前操作仅限 GM。";
  if (error?.code === "40001") return "操作与另一项健康处理发生并发冲突；请刷新后重试。";
  if (error?.code === "55000") return "这条历史记录受当前健康事件链保护，不能直接修改；请先处理较新的有效事件。";
  if (error?.code === "23505" || message.includes("request_id already exists")) return "同一请求已用不同事实处理。请刷新并确认当前健康历史。";
  if (message.includes("must change the current stamina state")) return "体力调整前后相同，不会创建无意义的健康事件。";
  if (message.includes("requires a managed horse") || message.includes("cannot enable or disable stamina")) return "赛后处理不能启用或停止体力管理；请保留当前管理状态。";
  if (message.includes("latest active horse health event")) return "只能纠正或作废最新的有效健康事件；请先处理之后的健康记录。";
  if (message.includes("injury") && message.includes("reason is required")) return "请输入伤病处理原因。";
  if (message.includes("replacement injury") || message.includes("injury wp")) return "请填写完整且有效的伤病开始、结束 WP 时间。";
  if (message.includes("stamina") || error?.code === "23514") return "请检查体力值、说明及当前状态后重试。";
  return fallback;
}

function revalidateHorseHealth(horseId: string) {
  revalidatePath(`/admin/horses/${horseId}`);
  revalidatePath(`/horses/${horseId}`);
  revalidatePath("/admin/races");
  revalidatePath("/races");
  revalidatePath("/admin/race-results");
}

export async function recordPostRaceHealth(input: {
  horseId: string;
  actualRaceId: string;
  raceResultId: string;
  staminaAfter: number | null;
  notes: string;
  requestId: string;
  injury?: InjuryFacts | null;
}): Promise<HealthActionResult> {
  const { supabase } = await requireGM();
  if (!input.raceResultId || !input.requestId || (input.staminaAfter !== null && (!Number.isInteger(input.staminaAfter) || input.staminaAfter < 0 || input.staminaAfter > 100)) || !validInjuryFacts(input.injury)) {
    return { ok: false, message: "请填写有效的赛后体力与伤病事实。" };
  }
  const injury = input.injury ?? null;
  const { error } = await supabase.rpc("record_post_race_health", {
    p_request_id: input.requestId,
    p_race_result_id: input.raceResultId,
    p_stamina_after: input.staminaAfter,
    p_injury_start_year: injury?.startYear ?? null,
    p_injury_start_month: injury?.startMonth ?? null,
    p_injury_start_week: injury?.startWeek ?? null,
    p_injury_end_year: injury?.endYear ?? null,
    p_injury_end_month: injury?.endMonth ?? null,
    p_injury_end_week: injury?.endWeek ?? null,
    p_injury_notes: injury ? optionalText(injury.notes) : null,
    p_notes: optionalText(input.notes),
  });
  if (error) return { ok: false, message: healthError(error, "赛后健康状态保存失败，请刷新后重试。") };
  revalidateHorseHealth(input.horseId);
  revalidatePath(`/admin/race-results/${input.actualRaceId}`);
  return { ok: true, message: "赛后状态已记录。" };
}

export async function adjustHorseStamina(input: {
  horseId: string;
  staminaAfter: number | null;
  reason: string;
  requestId: string;
}): Promise<HealthActionResult> {
  const { supabase } = await requireGM();
  if (!input.horseId || !input.requestId || !optionalText(input.reason) || (input.staminaAfter !== null && (!Number.isInteger(input.staminaAfter) || input.staminaAfter < 0 || input.staminaAfter > 100))) {
    return { ok: false, message: "请输入 0–100 的整数体力（或选择停止管理）及调整原因。" };
  }

  const { error } = await supabase.rpc("adjust_horse_stamina", {
    p_horse_id: input.horseId,
    p_stamina_after: input.staminaAfter,
    p_reason: optionalText(input.reason),
    p_request_id: input.requestId,
  });
  if (error) return { ok: false, message: healthError(error, "体力调整失败，请刷新后重试。") };
  revalidateHorseHealth(input.horseId);
  return { ok: true, message: "体力状态已记录。" };
}

export async function createManualInjury(input: { horseId: string; injury: InjuryFacts }): Promise<HealthActionResult> {
  const { supabase } = await requireGM();
  if (!input.horseId || !validInjuryFacts(input.injury)) return { ok: false, message: "请填写有效的完整伤病 WP 开始和结束时间。" };
  const { error } = await supabase.rpc("create_manual_injury", {
    p_horse_id: input.horseId,
    p_wp_start_year: input.injury.startYear,
    p_wp_start_month: input.injury.startMonth,
    p_wp_start_week: input.injury.startWeek,
    p_wp_end_year: input.injury.endYear,
    p_wp_end_month: input.injury.endMonth,
    p_wp_end_week: input.injury.endWeek,
    p_notes: optionalText(input.injury.notes),
  });
  if (error) return { ok: false, message: healthError(error, "伤病创建失败，请刷新后重试。") };
  revalidateHorseHealth(input.horseId);
  return { ok: true, message: "伤病事件已创建。" };
}

export async function resolveHorseInjury(input: { horseId: string; injuryId: string; reason: string }): Promise<HealthActionResult> {
  const { supabase } = await requireGM();
  if (!input.injuryId || !optionalText(input.reason)) return { ok: false, message: "请输入伤病恢复确认原因。" };
  const { error } = await supabase.rpc("resolve_injury", { p_injury_id: input.injuryId, p_reason: optionalText(input.reason) });
  if (error) return { ok: false, message: healthError(error, "伤病恢复处理失败，请刷新后重试。") };
  revalidateHorseHealth(input.horseId);
  return { ok: true, message: "伤病已标记为恢复。" };
}

export async function voidHorseInjury(input: { horseId: string; injuryId: string; reason: string }): Promise<HealthActionResult> {
  const { supabase } = await requireGM();
  if (!input.injuryId || !optionalText(input.reason)) return { ok: false, message: "请输入伤病作废原因。" };
  const { error } = await supabase.rpc("void_injury", { p_injury_id: input.injuryId, p_reason: optionalText(input.reason) });
  if (error) return { ok: false, message: healthError(error, "伤病作废失败，请刷新后重试。") };
  revalidateHorseHealth(input.horseId);
  return { ok: true, message: "伤病已作废；历史会保留。" };
}

export async function correctLatestHorseHealthEvent(input: {
  horseId: string;
  healthEventId: string;
  staminaAfter: number | null;
  notes: string;
  reason: string;
  requestId: string;
  injury?: InjuryFacts | null;
}): Promise<HealthActionResult> {
  const { supabase } = await requireGM();
  if (!input.healthEventId || !input.requestId || !optionalText(input.reason) || (input.staminaAfter !== null && (!Number.isInteger(input.staminaAfter) || input.staminaAfter < 0 || input.staminaAfter > 100)) || !validInjuryFacts(input.injury)) {
    return { ok: false, message: "请填写有效的纠错事实、原因和体力值。" };
  }
  const injury = input.injury ?? null;
  const { error } = await supabase.rpc("correct_latest_horse_health_event", {
    p_health_event_id: input.healthEventId,
    p_stamina_after: input.staminaAfter,
    p_notes: optionalText(input.notes),
    p_reason: optionalText(input.reason),
    p_request_id: input.requestId,
    p_injury_start_year: injury?.startYear ?? null,
    p_injury_start_month: injury?.startMonth ?? null,
    p_injury_start_week: injury?.startWeek ?? null,
    p_injury_end_year: injury?.endYear ?? null,
    p_injury_end_month: injury?.endMonth ?? null,
    p_injury_end_week: injury?.endWeek ?? null,
    p_injury_notes: injury ? optionalText(injury.notes) : null,
  });
  if (error) return { ok: false, message: healthError(error, "健康事件纠错失败，请刷新后重试。") };
  revalidateHorseHealth(input.horseId);
  return { ok: true, message: "健康事件已纠错；原记录已作废并保留历史。" };
}

export async function voidLatestHorseHealthEvent(input: { horseId: string; healthEventId: string; reason: string }): Promise<HealthActionResult> {
  const { supabase } = await requireGM();
  if (!input.healthEventId || !optionalText(input.reason)) return { ok: false, message: "请输入健康事件作废原因。" };
  const { error } = await supabase.rpc("void_latest_horse_health_event", { p_health_event_id: input.healthEventId, p_reason: optionalText(input.reason) });
  if (error) return { ok: false, message: healthError(error, "健康事件作废失败，请刷新后重试。") };
  revalidateHorseHealth(input.horseId);
  return { ok: true, message: "健康事件已作废；当前体力已回退。" };
}
