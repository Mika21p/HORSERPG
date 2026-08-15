"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";

import { requireGM } from "@/lib/auth/session";

const sessionStatuses = new Set(["DRAFT", "OPEN", "CLOSED", "REVIEWING"]);

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

function utcDateTime(formData: FormData, name: string) {
  const value = requiredText(formData, name);
  if (!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(?::\d{2})?$/.test(value)) {
    return null;
  }

  const date = new Date(`${value}Z`);
  return Number.isNaN(date.getTime()) ? null : date.toISOString();
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
  const startsAt = utcDateTime(formData, "starts_at");
  const endsAt = utcDateTime(formData, "ends_at");

  if (!wpYear || !startsAt || !endsAt || new Date(endsAt) <= new Date(startsAt)) {
    redirectWithNotice("/admin/foal-trade", "请填写有效的 WP 年份、UTC 开始时间和晚于开始时间的截止时间。");
  }

  const { error } = await supabase.from("foal_trade_sessions").insert({
    wp_year: wpYear,
    starts_at: startsAt,
    ends_at: endsAt,
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
  const startsAt = utcDateTime(formData, "starts_at");
  const endsAt = utcDateTime(formData, "ends_at");

  if (!startsAt || !endsAt || new Date(endsAt) <= new Date(startsAt)) {
    redirectWithNotice(`/admin/foal-trade/${sessionId}`, "请填写有效的 UTC 开始时间和截止时间。");
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
    .update({ starts_at: startsAt, ends_at: endsAt })
    .eq("id", sessionId);

  if (error) {
    redirectWithNotice(`/admin/foal-trade/${sessionId}`, "庭先时间保存失败。");
  }

  revalidateTrade(sessionId);
  redirectWithNotice(`/admin/foal-trade/${sessionId}`, "庭先现实时间已更新。");
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
