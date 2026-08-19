"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";

import { requireGM } from "@/lib/auth/session";

const sessionStatuses = new Set(["DRAFT", "OPEN", "CLOSED", "REVIEWING"]);
const scheduleDurations = new Set(["1", "3", "6", "12", "24", "72", "168"]);
const chinaStandardTimeOffsetMs = 8 * 60 * 60 * 1000;

function redirectWithNotice(path: string, notice: string): never {
  redirect(`${path}?notice=${encodeURIComponent(notice)}`);
}

function requiredText(formData: FormData, name: string) {
  return String(formData.get(name) ?? "").trim();
}

function positiveInteger(formData: FormData, name: string) {
  const value = requiredText(formData, name);
  return /^[1-9]\d*$/.test(value) ? value : null;
}

function nonNegativeInteger(formData: FormData, name: string) {
  const value = requiredText(formData, name);
  return /^\d+$/.test(value) ? value : null;
}

function chinaSchedule(formData: FormData) {
  const date = requiredText(formData, "start_date");
  const time = requiredText(formData, "start_time");
  const durationHours = requiredText(formData, "duration_hours");

  if (!/^\d{4}-\d{2}-\d{2}$/.test(date)
    || !/^\d{2}:\d{2}$/.test(time)
    || !scheduleDurations.has(durationHours)) {
    return null;
  }

  // Treat the selected date/time as China Standard Time wall-clock input, not
  // the browser's timezone. PostgreSQL continues to store timestamptz facts.
  const wallClock = new Date(`${date}T${time}:00.000Z`);
  if (Number.isNaN(wallClock.getTime())
    || wallClock.toISOString().slice(0, 10) !== date
    || wallClock.toISOString().slice(11, 16) !== time) {
    return null;
  }

  const startsAt = new Date(wallClock.getTime() - chinaStandardTimeOffsetMs);
  const endsAt = new Date(startsAt.getTime() + Number(durationHours) * 60 * 60 * 1000);

  if (startsAt.getTime() <= Date.now()) {
    return null;
  }

  return {
    startsAt: startsAt.toISOString(),
    endsAt: endsAt.toISOString(),
  };
}

function revalidateTrade(sessionId?: string) {
  revalidatePath("/foal-trade");
  revalidatePath("/admin/foal-trade");
  revalidatePath("/horses");
  revalidatePath("/admin/horses");

  if (sessionId) {
    revalidatePath(`/foal-trade/${sessionId}`);
    revalidatePath(`/admin/foal-trade/${sessionId}`);
  }
}

export async function createFoalTradeSession(formData: FormData) {
  const { supabase } = await requireGM();
  const wpYear = positiveInteger(formData, "wp_year");
  const schedule = chinaSchedule(formData);

  if (!wpYear || !schedule) {
    redirectWithNotice("/admin/foal-trade", "请选择未来的中国标准开始日期、开始时刻与报价时长。");
  }

  const { error } = await supabase.from("foal_trade_sessions").insert({
    wp_year: wpYear,
    starts_at: schedule.startsAt,
    ends_at: schedule.endsAt,
    status: "DRAFT",
  });

  if (error) {
    redirectWithNotice("/admin/foal-trade", "庭先届次创建失败。每个 WP 年份只能存在一届庭先。");
  }

  revalidateTrade();
  redirectWithNotice("/admin/foal-trade", "庭先届次已创建为草稿。请先加入 Lot，再开放报名。");
}

export async function updateFoalTradeSessionSchedule(sessionId: string, formData: FormData) {
  const { supabase } = await requireGM();
  const schedule = chinaSchedule(formData);

  if (!schedule) {
    redirectWithNotice(`/admin/foal-trade/${sessionId}`, "请选择未来的中国标准开始日期、开始时刻与报价时长。");
  }

  const { data: session } = await supabase
    .from("foal_trade_sessions")
    .select("status, starts_at")
    .eq("id", sessionId)
    .maybeSingle();

  if (!session || session.status !== "DRAFT" || new Date(session.starts_at) <= new Date()) {
    redirectWithNotice(`/admin/foal-trade/${sessionId}`, "仅未开始的草稿届次可以调整现实时间。");
  }

  const { error } = await supabase
    .from("foal_trade_sessions")
    .update({ starts_at: schedule.startsAt, ends_at: schedule.endsAt })
    .eq("id", sessionId);

  if (error) {
    redirectWithNotice(`/admin/foal-trade/${sessionId}`, "庭先时间保存失败。");
  }

  revalidateTrade(sessionId);
  redirectWithNotice(`/admin/foal-trade/${sessionId}`, "庭先时间已按中国标准时间与所选时长更新。");
}

export async function updateFoalTradeSessionStatus(sessionId: string, formData: FormData) {
  const { supabase } = await requireGM();
  const status = requiredText(formData, "status");

  if (!sessionStatuses.has(status)) {
    redirectWithNotice(`/admin/foal-trade/${sessionId}`, "请选择可由 GM 管理的庭先状态。");
  }

  const { error } = await supabase
    .from("foal_trade_sessions")
    .update({ status })
    .eq("id", sessionId);

  if (error) {
    redirectWithNotice(`/admin/foal-trade/${sessionId}`, "庭先状态更新失败。");
  }

  revalidateTrade(sessionId);
  redirectWithNotice(`/admin/foal-trade/${sessionId}`, "庭先状态已更新。报价与结算仍由数据库服务器时间和 RPC 最终裁定。");
}

export async function createFoalTradeLot(sessionId: string, formData: FormData) {
  const { supabase } = await requireGM();
  const horseId = requiredText(formData, "horse_id");
  const minimumPrice = nonNegativeInteger(formData, "minimum_price");

  if (!horseId || minimumPrice === null) {
    redirectWithNotice(`/admin/foal-trade/${sessionId}`, "请选择符合条件的 FOAL，并填写非负最低报价。");
  }

  const { data: session } = await supabase
    .from("foal_trade_sessions")
    .select("status, starts_at")
    .eq("id", sessionId)
    .maybeSingle();

  if (!session || session.status !== "DRAFT" || new Date(session.starts_at) <= new Date()) {
    redirectWithNotice(`/admin/foal-trade/${sessionId}`, "仅未开始的草稿届次可以加入 Lot。");
  }

  const { error } = await supabase.from("foal_trade_lots").insert({
    session_id: sessionId,
    horse_id: horseId,
    minimum_price: minimumPrice,
  });

  if (error) {
  redirectWithNotice(`/admin/foal-trade/${sessionId}`, "Lot 创建失败。Horse 必须是同 WP 出生批次、未归属且处于 FOAL；同一 Horse 只能参加一次庭先。");
  }

  revalidateTrade(sessionId);
  redirectWithNotice(`/admin/foal-trade/${sessionId}`, "庭先 Lot 已创建。");
}

function draftRemovalErrorNotice(message: string | undefined) {
  const normalized = message?.toLowerCase() ?? "";
  if (normalized.includes("non-empty removal reason")) {
    return "移除草稿必须填写非空原因。";
  }
  if (normalized.includes("only a gm")) {
    return "当前操作仅限 GM。";
  }
  if (normalized.includes("unstarted") || normalized.includes("player intent") || normalized.includes("settlement history")) {
    return "只能移除尚未开始且没有询问、报价或结算历史的草稿配置。";
  }
  return "草稿移除未被数据库接受。请刷新后确认当前状态。";
}

export async function removeFoalTradeDraftLot(sessionId: string, lotId: string, formData: FormData) {
  const { supabase } = await requireGM();
  const reason = requiredText(formData, "removal_reason");

  if (!reason) {
    redirectWithNotice(`/admin/foal-trade/${sessionId}`, "移除 Lot 必须填写原因。");
  }

  const { error } = await supabase.rpc("remove_foal_trade_draft_lot", {
    p_lot_id: lotId,
    p_reason: reason,
  });

  if (error) {
    redirectWithNotice(`/admin/foal-trade/${sessionId}`, draftRemovalErrorNotice(error.message));
  }

  revalidateTrade(sessionId);
  redirectWithNotice(`/admin/foal-trade/${sessionId}`, "草稿 Lot 已移除；Horse 可以重新配置。移除原因已审计。");
}

export async function removeFoalTradeDraftSession(sessionId: string, formData: FormData) {
  const { supabase } = await requireGM();
  const reason = requiredText(formData, "removal_reason");

  if (!reason) {
    redirectWithNotice(`/admin/foal-trade/${sessionId}`, "移除草稿届次必须填写原因。");
  }

  const { error } = await supabase.rpc("remove_foal_trade_draft_session", {
    p_session_id: sessionId,
    p_reason: reason,
  });

  if (error) {
    redirectWithNotice(`/admin/foal-trade/${sessionId}`, draftRemovalErrorNotice(error.message));
  }

  revalidateTrade(sessionId);
  redirectWithNotice("/admin/foal-trade", "草稿庭先届次及其未开始 Lot 已移除。所有移除均已审计。");
}

export async function replyToFoalTradeInquiry(sessionId: string, inquiryId: string, formData: FormData) {
  const { supabase } = await requireGM();
  const comment = requiredText(formData, "gm_comment");

  if (!comment) {
    redirectWithNotice(`/admin/foal-trade/${sessionId}`, "GM 回复不能为空。");
  }

  const { error } = await supabase
    .from("foal_trade_inquiries")
    .update({ gm_comment: comment })
    .eq("id", inquiryId)
    .eq("session_id", sessionId);

  if (error) {
    redirectWithNotice(`/admin/foal-trade/${sessionId}`, "GM 询问回复保存失败。 ");
  }

  revalidateTrade(sessionId);
  redirectWithNotice(`/admin/foal-trade/${sessionId}`, "GM 回复已保存，仅该 PLAYER 可读取。");
}

function settlementErrorNotice(message: string | undefined) {
  const normalized = message?.toLowerCase() ?? "";
  if (normalized.includes("before the session deadline")) {
    return "尚未到达数据库服务器认定的截止时间，不能结算。";
  }
  if (normalized.includes("status is not eligible")) {
    return "该届次当前状态不可结算。请使用 OPEN（已截止）、CLOSED 或 REVIEWING。";
  }
  if (normalized.includes("sufficient funds")) {
    return "所选 Owner 的账户资金与其他冻结不足以完成结算。未产生任何扣款或归属变更。";
  }
  if (normalized.includes("override requires")) {
    return "GM 例外裁定必须选择另一条有效报价并填写非空理由。";
  }
  return "庭先结算失败。请检查 Lot 状态、截止时间和有效报价后重试。";
}

export async function settleFoalTradeLot(sessionId: string, lotId: string) {
  const { supabase } = await requireGM();
  const { error } = await supabase.rpc("settle_foal_trade_lot", {
    p_lot_id: lotId,
    p_reason: null,
  });

  if (error) {
    redirectWithNotice(`/admin/foal-trade/${sessionId}`, settlementErrorNotice(error.message));
  }

  revalidateTrade(sessionId);
  redirectWithNotice(`/admin/foal-trade/${sessionId}`, "Lot 已按系统推荐结果结算。重复提交不会重复扣款。");
}

export async function settleFoalTradeLotOverride(sessionId: string, lotId: string, formData: FormData) {
  const { supabase } = await requireGM();
  const selectedOfferId = requiredText(formData, "selected_offer_id");
  const overrideReason = requiredText(formData, "override_reason");

  if (!selectedOfferId || !overrideReason) {
    redirectWithNotice(`/admin/foal-trade/${sessionId}`, "GM 例外裁定必须选择另一条有效报价，并填写非空裁定理由。");
  }

  const { error } = await supabase.rpc("settle_foal_trade_lot_override", {
    p_lot_id: lotId,
    p_selected_offer_id: selectedOfferId,
    p_override_reason: overrideReason,
  });

  if (error) {
    redirectWithNotice(`/admin/foal-trade/${sessionId}`, settlementErrorNotice(error.message));
  }

  revalidateTrade(sessionId);
  redirectWithNotice(`/admin/foal-trade/${sessionId}`, "GM 例外裁定已结算，并已写入审计记录。重复提交不会重复扣款。");
}
