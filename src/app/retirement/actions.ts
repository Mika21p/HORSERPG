"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";

import { requirePlayer } from "@/lib/auth/session";

type DatabaseError = { code?: string; message?: string } | null;

function messageForRetirementError(error: DatabaseError, operation: "submit" | "withdraw") {
  const message = error?.message?.toLowerCase() ?? "";

  if (message.includes("only a player") || message.includes("requesting owner") || message.includes("only that player owner")) {
    return "该 Horse 或退役申请不属于你的 Owner。";
  }
  if (message.includes("aged at least 3")) return "Owner 主动申请退役需要 Horse 已满 3 岁。";
  if (message.includes("only an active horse")) return "只有现役 Horse 可以申请退役。";
  if (message.includes("different pending retirement request")) return "该 Horse 已有另一条退役申请正在处理中。";
  if (message.includes("only a pending owner retirement request")) return "只有等待审核的 Owner 主动退役申请可以撤回。";
  if (message.includes("not retire_pending")) return "该 Horse 当前状态已变化，请刷新后查看。";
  if (message.includes("game state must be initialized")) return "GM 尚未设置当前 Winning Post 时间，暂时不能申请退役。";

  return operation === "withdraw"
    ? "撤回退役申请失败，请刷新后重试。"
    : "提交退役申请失败，请检查 Horse 状态后重试。";
}

function safeReturnPath(horseId: string, requestedPath: string) {
  return requestedPath === "/retirement" ? "/retirement" : `/horses/${horseId}`;
}

function revalidateRetirementPages(horseId: string) {
  revalidatePath(`/horses/${horseId}`);
  revalidatePath("/horses");
  revalidatePath("/retirement");
  revalidatePath("/admin/retirement");
  revalidatePath(`/admin/horses/${horseId}`);
}

export async function submitHorseRetirementRequest(horseId: string, formData: FormData) {
  const { supabase } = await requirePlayer();
  const note = String(formData.get("player_note") ?? "").trim() || null;
  const returnPath = safeReturnPath(horseId, String(formData.get("return_path") ?? ""));

  if (!horseId) {
    redirect(`${returnPath}?notice=${encodeURIComponent("未找到要申请退役的 Horse。")}`);
  }

  const { error } = await supabase.rpc("submit_horse_retirement_request", {
    p_horse_id: horseId,
    p_player_note: note,
  });

  if (error) {
    redirect(`${returnPath}?notice=${encodeURIComponent(messageForRetirementError(error, "submit"))}`);
  }

  revalidateRetirementPages(horseId);
  redirect(`${returnPath}?notice=${encodeURIComponent("退役申请已提交。Horse 已进入退役处理中，等待 GM 审核；这不会立即退役或释放奖金。")}`);
}

export async function withdrawHorseRetirementRequest(
  horseId: string,
  requestId: string,
  requestedPath: string,
) {
  const { supabase } = await requirePlayer();
  const returnPath = safeReturnPath(horseId, requestedPath);

  if (!horseId || !requestId) {
    redirect(`${returnPath}?notice=${encodeURIComponent("未找到要撤回的退役申请。")}`);
  }

  const { error } = await supabase.rpc("withdraw_horse_retirement_request", {
    p_request_id: requestId,
  });

  if (error) {
    redirect(`${returnPath}?notice=${encodeURIComponent(messageForRetirementError(error, "withdraw"))}`);
  }

  revalidateRetirementPages(horseId);
  redirect(`${returnPath}?notice=${encodeURIComponent("退役申请已撤回，Horse 已恢复为现役状态。")}`);
}
