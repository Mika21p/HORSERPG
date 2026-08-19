"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";

import { requireGM } from "@/lib/auth/session";

type DatabaseError = { code?: string; message?: string } | null;

const raceKinds = new Set(["CATALOG", "MAIDEN", "CONDITION", "OTHER"]);
const catalogGrades = new Set(["OP", "G3", "G2", "G1"]);

function redirectWithNotice(notice: string): never {
  redirect(`/admin/races?notice=${encodeURIComponent(notice)}`);
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

function catalogPayload(formData: FormData) {
  const name = text(formData, "name");
  const grade = text(formData, "grade");
  const month = text(formData, "default_wp_month");
  const week = text(formData, "default_wp_week");

  if (!name || !catalogGrades.has(grade) || !/^\d+$/.test(month) || !/^\d+$/.test(week)) return null;
  const defaultWpMonth = Number(month);
  const defaultWpWeek = Number(week);
  if (defaultWpMonth < 1 || defaultWpMonth > 12 || defaultWpWeek < 1 || defaultWpWeek > 5) return null;

  return {
    name,
    grade,
    default_wp_month: defaultWpMonth,
    default_wp_week: defaultWpWeek,
    is_active: formData.get("is_active") === "on",
  };
}

function gmRaceError(error: DatabaseError, action: "confirm" | "reject" | "direct" | "catalog") {
  const message = error?.message?.toLowerCase() ?? "";

  if (message.includes("only a gm")) return "当前操作仅限 GM。";
  if (message.includes("only pending") || message.includes("confirmed race-entry request may only")) return "该报名已被处理或最终信息与已有确认不一致。请刷新后查看最新状态。";
  if (message.includes("only active")) return "Horse 当前不是 ACTIVE，无法确认或直接安排赛程。";
  if (message.includes("ownership no longer")) return "Horse 的 Owner 已变化，不能确认这条原报名。";
  if (message.includes("cannot be earlier") || message.includes("wp time is invalid")) return "最终 WP 时间必须是当前周或未来周。";
  if (message.includes("active injury")) return "最终赛程落在 ACTIVE 伤病覆盖期内；伤病结束周仍不可参赛。";
  if (message.includes("already has a different")) return "该 Horse 本周已有其他已确认赛程。";
  if (message.includes("does not exist or is inactive")) return "所选固定比赛不存在或已停用。";
  if (message.includes("race kind") || message.includes("race identity") || message.includes("catalog race") || message.includes("non-catalog")) return "请完整填写最终比赛类型和对应比赛信息。";
  if (message.includes("requires an existing horse with an owner")) return "直接安排赛程需要一匹已归属的 Horse。";
  if (message.includes("duplicate key") || error?.code === "23505") return action === "catalog" ? "比赛目录名称已存在。" : "该 Horse 本周已有其他已确认赛程。";

  if (action === "catalog") return "比赛目录保存失败，请检查名称、级别与默认时间。";
  if (action === "reject") return "拒绝报名失败，请刷新后重试。";
  return action === "direct" ? "直接安排赛程失败，请检查最终条件后重试。" : "确认赛程失败，请刷新后重试。";
}

function revalidateRacePages() {
  revalidatePath("/races");
  revalidatePath("/admin/races");
}

export async function confirmRaceEntryRequest(requestId: string, formData: FormData) {
  const { supabase } = await requireGM();
  const time = wpTime(formData);
  const identity = raceIdentity(formData);
  if (!requestId || !time || !identity) {
    redirectWithNotice("请完整填写最终 WP 时间和比赛信息。");
  }

  const { error } = await supabase.rpc("confirm_race_entry_request", {
    p_request_id: requestId,
    p_confirmed_wp_year: time.year,
    p_confirmed_wp_month: time.month,
    p_confirmed_wp_week: time.week,
    p_confirmed_race_kind: identity.kind,
    p_confirmed_race_catalog_id: identity.catalogId,
    p_confirmed_race_label: identity.label,
    p_confirmed_jockey: optionalText(formData, "jockey"),
    p_confirmed_running_style: optionalText(formData, "running_style"),
    p_gm_note: optionalText(formData, "note"),
  });
  if (error) redirectWithNotice(gmRaceError(error, "confirm"));

  revalidateRacePages();
  redirectWithNotice("最终赛程已确认。PLAYER 可看到原报名与最终确认的准确对比。");
}

export async function rejectRaceEntryRequest(requestId: string, formData: FormData) {
  const { supabase } = await requireGM();
  const { error } = await supabase.rpc("reject_race_entry_request", {
    p_request_id: requestId,
    p_rejection_reason: optionalText(formData, "rejection_reason"),
  });
  if (error) redirectWithNotice(gmRaceError(error, "reject"));

  revalidateRacePages();
  redirectWithNotice("报名已拒绝。PLAYER 将看到拒绝状态和可选原因。");
}

export async function createDirectRaceEntry(formData: FormData) {
  const { supabase } = await requireGM();
  const horseId = text(formData, "horse_id");
  const time = wpTime(formData);
  const identity = raceIdentity(formData);
  if (!horseId || !time || !identity) redirectWithNotice("请选择 Horse，并完整填写最终 WP 时间和比赛信息。");

  const { error } = await supabase.rpc("create_gm_confirmed_race_entry", {
    p_horse_id: horseId,
    p_confirmed_wp_year: time.year,
    p_confirmed_wp_month: time.month,
    p_confirmed_wp_week: time.week,
    p_confirmed_race_kind: identity.kind,
    p_confirmed_race_catalog_id: identity.catalogId,
    p_confirmed_race_label: identity.label,
    p_confirmed_jockey: optionalText(formData, "jockey"),
    p_confirmed_running_style: optionalText(formData, "running_style"),
    p_gm_note: optionalText(formData, "note"),
  });
  if (error) redirectWithNotice(gmRaceError(error, "direct"));

  revalidateRacePages();
  redirectWithNotice("GM 直接赛程已保存；相同最终事实的网络重试会安全复用原记录。");
}

export async function createRaceCatalog(formData: FormData) {
  const { supabase } = await requireGM();
  const payload = catalogPayload(formData);
  if (!payload) redirectWithNotice("请填写比赛名称、级别和有效的默认月 / 周。");

  const { error } = await supabase.from("race_catalog").insert(payload);
  if (error) redirectWithNotice(gmRaceError(error, "catalog"));

  revalidateRacePages();
  redirectWithNotice("比赛目录已创建。默认时间只用于表单建议，不会修改既有赛程。");
}

export async function updateRaceCatalog(catalogId: string, formData: FormData) {
  const { supabase } = await requireGM();
  const payload = catalogPayload(formData);
  if (!catalogId || !payload) redirectWithNotice("请填写比赛名称、级别和有效的默认月 / 周。");

  const { error } = await supabase.from("race_catalog").update(payload).eq("id", catalogId);
  if (error) redirectWithNotice(gmRaceError(error, "catalog"));

  revalidateRacePages();
  redirectWithNotice("比赛目录已更新。停用只影响新的选择，不会移除历史引用。");
}
