"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";

import { requirePlayer } from "@/lib/auth/session";

type DatabaseError = { code?: string; message?: string } | null;

const raceKinds = new Set(["CATALOG", "MAIDEN", "CONDITION", "OTHER"]);

function redirectWithNotice(notice: string): never {
  redirect(`/races?notice=${encodeURIComponent(notice)}`);
}

function text(formData: FormData, name: string) {
  return String(formData.get(name) ?? "").trim();
}

function optionalText(formData: FormData, name: string) {
  return text(formData, name) || null;
}

function wpTime(formData: FormData) {
  const year = text(formData, "wp_year");
  const month = text(formData, "wp_month");
  const week = text(formData, "wp_week");

  if (!/^[1-9]\d*$/.test(year) || !/^\d+$/.test(month) || !/^\d+$/.test(week)) {
    return null;
  }

  const numericMonth = Number(month);
  const numericWeek = Number(week);
  if (numericMonth < 1 || numericMonth > 12 || numericWeek < 1 || numericWeek > 5) {
    return null;
  }

  return { year: Number(year), month: numericMonth, week: numericWeek };
}

function raceIdentity(formData: FormData) {
  const kind = text(formData, "race_kind");
  const catalogId = optionalText(formData, "race_catalog_id");
  const label = optionalText(formData, "race_label");

  if (!raceKinds.has(kind)) {
    return null;
  }
  if (kind === "CATALOG") {
    return catalogId && !label ? { kind, catalogId, label: null } : null;
  }

  return !catalogId && label ? { kind, catalogId: null, label } : null;
}

function playerRaceError(error: DatabaseError, action: "submit" | "withdraw") {
  const message = error?.message?.toLowerCase() ?? "";

  if (message.includes("only active")) return "该 Horse 当前不是 ACTIVE，不能提交比赛报名。";
  if (message.includes("belongs to the requesting owner") || message.includes("only that player owner")) return "该 Horse 或报名不属于你的 Owner。";
  if (message.includes("cannot be earlier") || message.includes("wp time is invalid")) return "报名时间必须是当前 Winning Post 周或未来周。";
  if (message.includes("does not exist or is inactive")) return "所选固定比赛不存在或已停用。";
  if (message.includes("race kind") || message.includes("race identity") || message.includes("catalog race") || message.includes("non-catalog")) return "请完整填写比赛类型和对应比赛信息。";
  if (message.includes("only pending")) return action === "withdraw" ? "只有等待审核的报名可以撤回。" : "该报名已被处理，请刷新后查看最新状态。";

  return action === "withdraw" ? "撤回报名失败，请刷新后重试。" : "报名提交失败，请检查 Horse、时间和比赛信息后重试。";
}

function revalidateRacePages() {
  revalidatePath("/races");
  revalidatePath("/admin/races");
}

export async function submitRaceEntryRequest(formData: FormData) {
  const { supabase } = await requirePlayer();
  const horseId = text(formData, "horse_id");
  const time = wpTime(formData);
  const identity = raceIdentity(formData);

  if (!horseId || !time || !identity) {
    redirectWithNotice("请选择 Horse，填写有效 WP 时间，并完整选择比赛信息。");
  }

  const { error } = await supabase.rpc("submit_race_entry_request", {
    p_horse_id: horseId,
    p_requested_wp_year: time.year,
    p_requested_wp_month: time.month,
    p_requested_wp_week: time.week,
    p_requested_race_kind: identity.kind,
    p_requested_race_catalog_id: identity.catalogId,
    p_requested_race_label: identity.label,
    p_requested_jockey: optionalText(formData, "jockey"),
    p_requested_running_style: optionalText(formData, "running_style"),
    p_player_note: optionalText(formData, "note"),
  });

  if (error) {
    redirectWithNotice(playerRaceError(error, "submit"));
  }

  revalidateRacePages();
  redirectWithNotice("报名意向已提交，等待 GM 确认。它尚不是已确认赛程。");
}

export async function withdrawRaceEntryRequest(requestId: string) {
  const { supabase } = await requirePlayer();

  if (!requestId) {
    redirectWithNotice("未找到要撤回的报名。请刷新后重试。");
  }

  const { error } = await supabase.rpc("withdraw_race_entry_request", {
    p_request_id: requestId,
  });

  if (error) {
    redirectWithNotice(playerRaceError(error, "withdraw"));
  }

  revalidateRacePages();
  redirectWithNotice("报名意向已撤回。");
}
