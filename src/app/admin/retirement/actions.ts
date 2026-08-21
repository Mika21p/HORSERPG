"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";

import { requireGM } from "@/lib/auth/session";

type DatabaseError = { code?: string; message?: string } | null;

function text(formData: FormData, name: string) {
  return String(formData.get(name) ?? "").trim();
}

function noticePath(notice: string): never {
  redirect(`/admin/retirement?notice=${encodeURIComponent(notice)}`);
}

function adminRetirementError(error: DatabaseError, action: "create" | "reject" | "confirm") {
  const message = error?.message?.toLowerCase() ?? "";

  if (message.includes("only a gm")) return "当前操作仅限 GM。";
  if (message.includes("does not exist")) return "未找到所选 Horse 或退役申请，请刷新后重试。";
  if (message.includes("different pending retirement request")) return "该 Horse 已有另一条退役申请正在处理中。";
  if (message.includes("only an active horse")) return "只有 ACTIVE Horse 可以创建退役申请。";
  if (message.includes("requires an existing owned horse")) return "强制退役申请只能用于已有 Owner 的 Horse。";
  if (message.includes("at least 9 current g1 wins")) return "G1 九胜退役要求该 Horse 当前至少有 9 场有效 G1 冠军。";
  if (message.includes("wp_lifespan retirement requires")) return "WP 寿命裁定必须填写原因。";
  if (message.includes("rejection reason is required")) return "拒绝退役申请必须填写原因。";
  if (message.includes("future confirmed race entries")) return "该 Horse 仍有未来已确认赛程；请先由 GM 按既有赛程流程处理，不能确认退役。";
  if (message.includes("not retire_pending")) return "Horse 当前不在退役处理中，请刷新后查看。";
  if (message.includes("only a pending retirement request")) return "只有等待处理的退役申请可以继续此操作。";
  if (message.includes("cannot have its reason changed")) return "该拒绝记录已经完成，不能更改拒绝原因。";
  if (message.includes("game state must be initialized")) return "请先初始化 Game State，再确认退役。";

  if (action === "confirm") return "确认退役失败；数据库事务已整体回滚，请刷新后核对并重试。";
  if (action === "reject") return "拒绝退役申请失败，请刷新后重试。";
  return "创建强制退役申请失败，请检查 Horse 状态和输入内容后重试。";
}

function revalidateRetirementPages(horseId?: string) {
  revalidatePath("/admin/retirement");
  revalidatePath("/retirement");
  revalidatePath("/horses");
  revalidatePath("/admin/horses");
  if (horseId) {
    revalidatePath(`/horses/${horseId}`);
    revalidatePath(`/admin/horses/${horseId}`);
  }
}

export async function createGmRetirementRequest(formData: FormData) {
  const { supabase } = await requireGM();
  const horseId = text(formData, "horse_id");
  const requestKind = text(formData, "request_kind");
  const reason = text(formData, "gm_reason") || null;

  if (!horseId || (requestKind !== "G1_LIMIT" && requestKind !== "WP_LIFESPAN")) {
    noticePath("请选择已有 Owner 的 Horse 与合法的强制退役类型。");
  }
  if (requestKind === "WP_LIFESPAN" && !reason) {
    noticePath("WP 寿命裁定必须填写原因。");
  }

  const { error } = await supabase.rpc("create_gm_retirement_request", {
    p_horse_id: horseId,
    p_request_kind: requestKind,
    p_gm_reason: reason,
  });
  if (error) noticePath(adminRetirementError(error, "create"));

  revalidateRetirementPages(horseId);
  noticePath("强制退役申请已创建。Horse 已进入退役处理中，仍需单独确认退役并结算奖金。");
}

export async function rejectHorseRetirementRequest(horseId: string, requestId: string, formData: FormData) {
  const { supabase } = await requireGM();
  const reason = text(formData, "reason");

  if (!horseId || !requestId || !reason) {
    noticePath("拒绝退役申请必须填写原因。");
  }

  const { error } = await supabase.rpc("reject_horse_retirement_request", {
    p_request_id: requestId,
    p_reason: reason,
  });
  if (error) noticePath(adminRetirementError(error, "reject"));

  revalidateRetirementPages(horseId);
  noticePath("退役申请已拒绝，Horse 已恢复为现役状态。");
}

export async function confirmHorseRetirementRequest(horseId: string, requestId: string) {
  const { supabase } = await requireGM();

  if (!horseId || !requestId) {
    noticePath("未找到要确认的退役申请。");
  }

  const { error } = await supabase.rpc("confirm_horse_retirement", {
    p_request_id: requestId,
  });
  if (error) noticePath(adminRetirementError(error, "confirm"));

  revalidateRetirementPages(horseId);
  noticePath("Horse 已确认退役；该 Horse 的所有待释放奖金已在同一事务中处理。重复确认不会重复放款。");
}
