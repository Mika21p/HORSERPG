"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";

import { requirePlayer } from "@/lib/auth/session";

type DatabaseError = { code?: string; message?: string } | null;

function redirectWithNotice(sessionId: string, notice: string): never {
  redirect(`/foal-trade/${sessionId}?notice=${encodeURIComponent(notice)}`);
}

function readAmount(formData: FormData) {
  const value = String(formData.get("amount") ?? "").trim();
  return /^\d+$/.test(value) ? value : null;
}

function playerErrorNotice(error: DatabaseError, action: "bid" | "withdraw" | "inquiry") {
  const message = error?.message?.toLowerCase() ?? "";

  if (message.includes("available funds")) {
    return "可用资金不足，无法冻结这笔秘密报价。";
  }
  if (message.includes("below the public minimum")) {
    return "报价不得低于该 Lot 的最低报价。";
  }
  if (message.includes("only one inquiry")) {
    return "本届 GM 询问机会已用于另一匹幼驹，不能更换。";
  }
  if (message.includes("no longer accepting") || message.includes("no active secret bid")) {
    return action === "inquiry"
      ? "本届庭先当前不能提交询问，可能尚未开放或已经截止。"
      : action === "withdraw"
        ? "当前不能撤回报价，可能已经截止或该报价不再有效。"
        : "本届庭先当前不能提交报价，可能尚未开放或已经截止。";
  }

  return action === "inquiry" ? "GM 询问提交失败，请稍后重试。" : "秘密报价操作失败，请稍后重试。";
}

async function ensureLotBelongsToSession(sessionId: string, lotId: string) {
  const { supabase } = await requirePlayer();
  const { data: lot } = await supabase
    .from("foal_trade_lots")
    .select("session_id")
    .eq("id", lotId)
    .eq("session_id", sessionId)
    .maybeSingle();

  return { lot, supabase };
}

function revalidatePlayerTrade(sessionId: string) {
  revalidatePath("/foal-trade");
  revalidatePath(`/foal-trade/${sessionId}`);
}

export async function submitSecretBid(sessionId: string, lotId: string, formData: FormData) {
  const amount = readAmount(formData);
  if (!amount) {
    redirectWithNotice(sessionId, "请输入非负整数金额。金额以游戏资金单位填写。");
  }

  const { lot, supabase } = await ensureLotBelongsToSession(sessionId, lotId);
  if (!lot) {
    redirectWithNotice(sessionId, "该 Lot 不存在或不属于本届庭先。");
  }

  const { error } = await supabase.rpc("submit_foal_trade_secret_bid", {
    p_lot_id: lotId,
    p_amount: amount,
  });

  if (error) {
    redirectWithNotice(sessionId, playerErrorNotice(error, "bid"));
  }

  revalidatePlayerTrade(sessionId);
  redirectWithNotice(sessionId, "你的秘密报价已保存；资金汇总已更新。");
}

export async function withdrawSecretBid(sessionId: string, lotId: string) {
  const { lot, supabase } = await ensureLotBelongsToSession(sessionId, lotId);
  if (!lot) {
    redirectWithNotice(sessionId, "该 Lot 不存在或不属于本届庭先。");
  }

  const { error } = await supabase.rpc("withdraw_foal_trade_secret_bid", {
    p_lot_id: lotId,
  });

  if (error) {
    redirectWithNotice(sessionId, playerErrorNotice(error, "withdraw"));
  }

  revalidatePlayerTrade(sessionId);
  redirectWithNotice(sessionId, "你的秘密报价已撤回；资金汇总已更新。");
}

export async function createTradeInquiry(sessionId: string, lotId: string) {
  const { lot, supabase } = await ensureLotBelongsToSession(sessionId, lotId);
  if (!lot) {
    redirectWithNotice(sessionId, "该 Lot 不存在或不属于本届庭先。");
  }

  const { error } = await supabase.rpc("create_foal_trade_inquiry", {
    p_lot_id: lotId,
  });

  if (error) {
    redirectWithNotice(sessionId, playerErrorNotice(error, "inquiry"));
  }

  revalidatePlayerTrade(sessionId);
  redirectWithNotice(sessionId, "GM 询问已提交。本届只能询问这一匹幼驹。");
}
