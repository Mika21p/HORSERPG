"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";

import { requireGM } from "@/lib/auth/session";

type DatabaseError = { code?: string; message?: string } | null;

const raceKinds = new Set(["CATALOG", "MAIDEN", "CONDITION", "OTHER"]);

export type RecordRaceResultInput = {
  confirmedRaceEntryId: string;
  actualRaceId: string;
  finishPosition: string;
  prizeAmount: string;
  actualJockey: string;
  actualRunningStyle: string;
  gmNote: string;
};

export type RaceResultActionResult = { ok: boolean; message: string };

function text(formData: FormData, name: string) {
  return String(formData.get(name) ?? "").trim();
}

function optionalText(formData: FormData, name: string) {
  return text(formData, name) || null;
}

function optionalValue(value: string) {
  return value.trim() || null;
}

function wpTime(formData: FormData) {
  const year = text(formData, "wp_year");
  const month = text(formData, "wp_month");
  const week = text(formData, "wp_week");

  if (!/^[1-9]\d*$/.test(year) || !/^\d+$/.test(month) || !/^\d+$/.test(week)) return null;
  const numericMonth = Number(month);
  const numericWeek = Number(week);
  if (numericMonth < 1 || numericMonth > 12 || numericWeek < 1 || numericWeek > 5) return null;
  return { year: Number(year), month: numericMonth, week: numericWeek };
}

function raceIdentity(formData: FormData) {
  const kind = text(formData, "race_kind");
  const catalogId = optionalText(formData, "race_catalog_id");
  const label = optionalText(formData, "race_label");

  if (!raceKinds.has(kind)) return null;
  if (kind === "CATALOG") return catalogId && !label ? { kind, catalogId, label: null } : null;
  return !catalogId && label ? { kind, catalogId: null, label } : null;
}

function noticePath(path: string, notice: string): never {
  redirect(`${path}?notice=${encodeURIComponent(notice)}`);
}

function raceResultError(error: DatabaseError, action: "actual" | "correction" | "record" | "void") {
  const message = error?.message?.toLowerCase() ?? "";

  if (message.includes("only a gm")) return "当前操作仅限 GM。";
  if (message.includes("cannot be later than the current game week")) return "实际比赛时间不能晚于当前游戏周。";
  if (message.includes("actual race does not exist")) return "未找到所选实际比赛。";
  if (message.includes("confirmed race entry does not exist")) return "未找到所选已确认赛程。";
  if (message.includes("use correction flow")) return "该赛程已有不同的有效赛果，请使用赛果纠错功能。";
  if (message.includes("already has a confirmed result") || message.includes("duplicate key") || error?.code === "23505") {
    return action === "actual" ? "该 WP 周的这场固定比赛已存在实际比赛记录。" : "该 Horse 在目标实际比赛中已有有效赛果。";
  }
  if (message.includes("correction reason is required") || message.includes("actual-race correction reason is required")) return "请输入纠错原因。";
  if (message.includes("void reason is required")) return "请输入作废原因。";
  if (message.includes("cannot have its void reason changed")) return "已作废赛果的作废原因不能修改。";
  if (message.includes("finish position") || message.includes("prize amount") || message.includes("race-result facts")) return "请填写 1–99 的名次与非负整数实际赏金。";
  if (message.includes("race identity") || message.includes("catalog") || message.includes("non-catalog")) return "请完整选择比赛类型及对应比赛信息。";

  if (action === "void") return "作废赛果失败，请刷新后重试。";
  if (action === "correction") return "赛果纠错失败，请检查填写内容后重试。";
  if (action === "actual") return "实际比赛保存失败，请检查时间和比赛信息后重试。";
  return "赛果录入失败，请检查该赛程、实际比赛和输入内容后重试。";
}

function revalidateRaceResultPages(actualRaceId?: string) {
  revalidatePath("/admin/race-results");
  if (actualRaceId) revalidatePath(`/admin/race-results/${actualRaceId}`);
  revalidatePath("/results");
}

export async function createActualRace(formData: FormData) {
  const { supabase } = await requireGM();
  const time = wpTime(formData);
  const identity = raceIdentity(formData);
  if (!time || !identity) noticePath("/admin/race-results", "请填写有效的实际 WP 时间和完整比赛信息。");

  const { data, error } = await supabase.rpc("create_actual_race", {
    p_wp_year: time.year,
    p_wp_month: time.month,
    p_wp_week: time.week,
    p_race_kind: identity.kind,
    p_race_catalog_id: identity.catalogId,
    p_race_label: identity.label,
  });
  if (error) noticePath("/admin/race-results", raceResultError(error, "actual"));

  const actualRace = (Array.isArray(data) ? data[0] : data) as { id?: string } | null;
  revalidateRaceResultPages(actualRace?.id);
  if (actualRace?.id) redirect(`/admin/race-results/${actualRace.id}?notice=${encodeURIComponent("实际比赛已创建。请明确选择要关联并录入赛果的已确认赛程。")}`);
  noticePath("/admin/race-results", "实际比赛已创建。请刷新后进入赛果录入。 ");
}

export async function correctActualRace(actualRaceId: string, formData: FormData) {
  const { supabase } = await requireGM();
  const time = wpTime(formData);
  const identity = raceIdentity(formData);
  const reason = optionalText(formData, "reason");
  if (!actualRaceId || !time || !identity || !reason) noticePath(`/admin/race-results/${actualRaceId}`, "请填写有效时间、完整比赛信息和纠错原因。");

  const { error } = await supabase.rpc("correct_actual_race", {
    p_actual_race_id: actualRaceId,
    p_wp_year: time.year,
    p_wp_month: time.month,
    p_wp_week: time.week,
    p_race_kind: identity.kind,
    p_race_catalog_id: identity.catalogId,
    p_race_label: identity.label,
    p_reason: reason,
  });
  if (error) noticePath(`/admin/race-results/${actualRaceId}`, raceResultError(error, "correction"));

  revalidateRaceResultPages(actualRaceId);
  noticePath(`/admin/race-results/${actualRaceId}`, "实际比赛已纠错；关联赛果仍保持同一 Actual Race 记录。");
}

export async function recordRaceResult(input: RecordRaceResultInput): Promise<RaceResultActionResult> {
  const { supabase } = await requireGM();
  if (!input.confirmedRaceEntryId || !input.actualRaceId || !/^\d+$/.test(input.finishPosition) || !/^\d+$/.test(input.prizeAmount)) {
    return { ok: false, message: "请填写 1–99 的名次与非负整数实际赏金。" };
  }

  const finishPosition = Number(input.finishPosition);
  if (finishPosition < 1 || finishPosition > 99) return { ok: false, message: "名次必须是 1–99 的整数。" };

  const { error } = await supabase.rpc("record_race_result", {
    p_confirmed_race_entry_id: input.confirmedRaceEntryId,
    p_actual_race_id: input.actualRaceId,
    p_finish_position: finishPosition,
    p_prize_amount: input.prizeAmount,
    p_actual_jockey: optionalValue(input.actualJockey),
    p_actual_running_style: optionalValue(input.actualRunningStyle),
    p_gm_note: optionalValue(input.gmNote),
  });

  if (error) return { ok: false, message: raceResultError(error, "record") };
  revalidateRaceResultPages(input.actualRaceId);
  return { ok: true, message: "已保存。" };
}

export async function correctRaceResult(resultId: string, formData: FormData) {
  const { supabase } = await requireGM();
  const actualRaceId = text(formData, "actual_race_id");
  const finishPosition = text(formData, "finish_position");
  const prizeAmount = text(formData, "prize_amount");
  const reason = optionalText(formData, "reason");
  if (!resultId || !actualRaceId || !/^\d+$/.test(finishPosition) || Number(finishPosition) < 1 || Number(finishPosition) > 99 || !/^\d+$/.test(prizeAmount) || !reason) {
    noticePath("/admin/race-results", "请填写目标实际比赛、有效名次、非负整数赏金与纠错原因。");
  }

  const { data: current } = await supabase.from("race_results").select("actual_race_id").eq("id", resultId).maybeSingle();
  const { error } = await supabase.rpc("correct_race_result", {
    p_race_result_id: resultId,
    p_actual_race_id: actualRaceId,
    p_finish_position: Number(finishPosition),
    p_prize_amount: prizeAmount,
    p_actual_jockey: optionalText(formData, "actual_jockey"),
    p_actual_running_style: optionalText(formData, "actual_running_style"),
    p_gm_note: optionalText(formData, "gm_note"),
    p_reason: reason,
  });
  const returnPath = current?.actual_race_id || actualRaceId;
  if (error) noticePath(`/admin/race-results/${returnPath}`, raceResultError(error, "correction"));

  revalidateRaceResultPages(returnPath);
  if (actualRaceId !== returnPath) revalidateRaceResultPages(actualRaceId);
  noticePath(`/admin/race-results/${actualRaceId}`, "赛果已纠错。公开页面仅显示当前有效事实。");
}

export async function voidRaceResult(resultId: string, actualRaceId: string, formData: FormData) {
  const { supabase } = await requireGM();
  const reason = optionalText(formData, "reason");
  if (!resultId || !actualRaceId || !reason) noticePath(`/admin/race-results/${actualRaceId}`, "请输入作废原因。 ");

  const { error } = await supabase.rpc("void_race_result", {
    p_race_result_id: resultId,
    p_reason: reason,
  });
  if (error) noticePath(`/admin/race-results/${actualRaceId}`, raceResultError(error, "void"));

  revalidateRaceResultPages(actualRaceId);
  noticePath(`/admin/race-results/${actualRaceId}`, "赛果已作废。历史记录保留，之后可以重新录入新的有效赛果。");
}
