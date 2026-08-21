"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";

import { requireGM } from "@/lib/auth/session";
import { createAdminClient } from "@/lib/supabase/admin";

const sexValues = new Set(["MALE", "FEMALE", "GELDING"]);
const lifeStageValues = new Set([
  "FOAL",
  "OWNED_FOAL",
  "TRAINING",
  "ACTIVE",
  "RETIRE_PENDING",
  "RETIRED",
  "BREEDING",
  "DISCARDED",
]);

function redirectWithNotice(path: string, notice: string): never {
  redirect(`${path}?notice=${encodeURIComponent(notice)}`);
}

function requiredText(formData: FormData, name: string) {
  return String(formData.get(name) ?? "").trim();
}

function optionalText(formData: FormData, name: string) {
  const value = requiredText(formData, name);
  return value || null;
}

function positiveInteger(formData: FormData, name: string) {
  const value = requiredText(formData, name);
  if (!/^[1-9]\d*$/.test(value)) {
    return null;
  }
  return value;
}

function nonNegativeInteger(formData: FormData, name: string) {
  const value = requiredText(formData, name);
  if (!/^\d+$/.test(value)) {
    return null;
  }
  return value;
}

function optionalId(formData: FormData, name: string) {
  const value = requiredText(formData, name);
  return value || null;
}

export async function createOwner(formData: FormData) {
  const { supabase } = await requireGM();
  const displayName = requiredText(formData, "display_name");
  const initialFunds = nonNegativeInteger(formData, "initial_funds");

  if (!displayName || initialFunds === null) {
    redirectWithNotice("/admin/owners", "请填写 Owner 名称和非负初始资金。");
  }

  const { error } = await supabase.from("owners").insert({
    display_name: displayName,
    initial_funds: initialFunds,
  });

  if (error) {
    redirectWithNotice("/admin/owners", "Owner 创建失败，请检查输入后重试。");
  }

  revalidatePath("/admin/owners");
  revalidatePath("/owners");
  redirectWithNotice("/admin/owners", "Owner 已创建。初始资金今后只能通过资金流水调整。");
}

export async function updateOwner(ownerId: string, formData: FormData) {
  const { supabase } = await requireGM();
  const displayName = requiredText(formData, "display_name");

  if (!displayName) {
    redirectWithNotice(`/admin/owners/${ownerId}`, "Owner 名称不能为空。");
  }

  const { error } = await supabase
    .from("owners")
    .update({ display_name: displayName })
    .eq("id", ownerId);

  if (error) {
    redirectWithNotice(`/admin/owners/${ownerId}`, "Owner 资料更新失败。");
  }

  revalidatePath("/admin/owners");
  revalidatePath(`/admin/owners/${ownerId}`);
  revalidatePath("/owners");
  revalidatePath(`/owners/${ownerId}`);
  redirectWithNotice(`/admin/owners/${ownerId}`, "Owner 公开资料已更新。");
}

export async function createPlayer(formData: FormData) {
  const { supabase } = await requireGM();
  const ownerId = requiredText(formData, "owner_id");
  const email = requiredText(formData, "email").toLowerCase();
  const password = String(formData.get("password") ?? "");
  const displayName = optionalText(formData, "display_name");

  if (!ownerId || !email.includes("@") || password.length < 8) {
    redirectWithNotice("/admin/users", "请选择 Owner，并提供有效邮箱和至少 8 位密码。");
  }

  const [{ data: owner }, { data: boundProfile }] = await Promise.all([
    supabase.from("owners").select("id").eq("id", ownerId).maybeSingle(),
    supabase
      .from("user_profiles")
      .select("id")
      .eq("owner_id", ownerId)
      .maybeSingle(),
  ]);

  if (!owner || boundProfile) {
    redirectWithNotice("/admin/users", "该 Owner 不存在或已经绑定 PLAYER。请选择空闲 Owner。");
  }

  const admin = createAdminClient();
  const { data: created, error: authError } = await admin.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
  });

  if (authError || !created.user) {
    redirectWithNotice("/admin/users", "PLAYER Auth 账号创建失败。邮箱可能已被使用。");
  }

  const { error: profileError } = await admin.from("user_profiles").insert({
    id: created.user.id,
    role: "PLAYER",
    owner_id: ownerId,
    display_name: displayName,
  });

  if (profileError) {
    const { error: rollbackError } = await admin.auth.admin.deleteUser(created.user.id);
    redirectWithNotice(
      "/admin/users",
      rollbackError
        ? "PLAYER 资料创建失败，且账号自动回滚失败。请按该邮箱人工检查。"
        : "PLAYER 资料创建失败，已自动回滚 Auth 账号。",
    );
  }

  revalidatePath("/admin/users");
  revalidatePath("/admin/owners");
  redirectWithNotice("/admin/users", "PLAYER 账号已创建并绑定 Owner。");
}

export async function updatePlayer(playerId: string, formData: FormData) {
  const { supabase } = await requireGM();
  const displayName = optionalText(formData, "display_name");
  const email = requiredText(formData, "email").toLowerCase();
  const password = String(formData.get("password") ?? "");

  if (!email.includes("@") || (password && password.length < 8)) {
    redirectWithNotice(`/admin/users/${playerId}`, "请提供有效邮箱；如要重设密码，密码至少应为 8 位。");
  }

  const { data: profile } = await supabase
    .from("user_profiles")
    .select("id, role")
    .eq("id", playerId)
    .maybeSingle();

  if (!profile || profile.role !== "PLAYER") {
    redirectWithNotice("/admin/users", "未找到要编辑的 PLAYER。GM 账号不能在此页面修改。");
  }

  const admin = createAdminClient();
  const { data: currentAuth, error: currentAuthError } = await admin.auth.admin.getUserById(playerId);

  if (currentAuthError || !currentAuth.user) {
    redirectWithNotice(`/admin/users/${playerId}`, "无法读取该 PLAYER 的登录账号。请检查 Auth 用户是否仍存在。");
  }

  const { error: profileError } = await supabase
    .from("user_profiles")
    .update({ display_name: displayName })
    .eq("id", playerId);

  if (profileError) {
    redirectWithNotice(`/admin/users/${playerId}`, "PLAYER 显示名更新失败。");
  }

  const authUpdates: { email?: string; email_confirm?: boolean; password?: string } = {};
  if (currentAuth.user.email?.toLowerCase() !== email) {
    authUpdates.email = email;
    authUpdates.email_confirm = true;
  }
  if (password) {
    authUpdates.password = password;
  }

  if (Object.keys(authUpdates).length) {
    const { error: authError } = await admin.auth.admin.updateUserById(playerId, authUpdates);

    if (authError) {
      redirectWithNotice(`/admin/users/${playerId}`, "登录邮箱或密码更新失败。该邮箱可能已被使用。");
    }
  }

  revalidatePath("/admin/users");
  revalidatePath(`/admin/users/${playerId}`);
  redirectWithNotice(`/admin/users/${playerId}`, "PLAYER 资料已更新。");
}

function getHorsePayload(formData: FormData) {
  const horseNumber = positiveInteger(formData, "horse_number");
  const birthYear = positiveInteger(formData, "birth_year");
  const foalName = requiredText(formData, "foal_name");
  const coatColor = requiredText(formData, "coat_color");
  const sireName = requiredText(formData, "sire_name");
  const sireLine = requiredText(formData, "sire_line");
  const broodmareSireName = requiredText(formData, "broodmare_sire_name");
  const sex = requiredText(formData, "sex");
  const lifeStage = requiredText(formData, "life_stage");

  if (
    !horseNumber ||
    !birthYear ||
    !foalName ||
    !coatColor ||
    !sireName ||
    !sireLine ||
    !broodmareSireName ||
    !sexValues.has(sex) ||
    !lifeStageValues.has(lifeStage)
  ) {
    return null;
  }

  return {
    horse_number: horseNumber,
    birth_year: birthYear,
    foal_name: foalName,
    name_katakana: optionalText(formData, "name_katakana"),
    translated_name: optionalText(formData, "translated_name"),
    sex,
    coat_color: coatColor,
    sire_name: sireName,
    sire_line: sireLine,
    dam_name: optionalText(formData, "dam_name"),
    broodmare_sire_name: broodmareSireName,
    current_jockey_name: optionalText(formData, "current_jockey_name"),
    current_trainer_name: optionalText(formData, "current_trainer_name"),
    life_stage: lifeStage,
  };
}

export async function createHorse(formData: FormData) {
  const { supabase } = await requireGM();
  const horse = getHorsePayload(formData);
  const ownerId = optionalId(formData, "owner_id");

  if (!horse) {
    redirectWithNotice("/admin/horses/new", "请完整填写必填 Horse 字段，并检查枚举值。");
  }

  const { data, error } = await supabase
    .from("horses")
    .insert({ ...horse, owner_id: ownerId })
    .select("id")
    .single();

  if (error || !data) {
    redirectWithNotice("/admin/horses/new", "Horse 创建失败。马号必须唯一，Owner 必须存在。");
  }

  revalidatePath("/admin/horses");
  revalidatePath("/horses");
  redirect(`/admin/horses/${data.id}?notice=${encodeURIComponent("Horse 已创建。")}`);
}

export async function updateHorse(horseId: string, formData: FormData) {
  const { supabase } = await requireGM();
  const horse = getHorsePayload(formData);

  if (!horse) {
    redirectWithNotice(`/admin/horses/${horseId}`, "请完整填写必填 Horse 字段，并检查枚举值。");
  }

  const { data: existingHorse } = await supabase
    .from("horses")
    .select("owner_id")
    .eq("id", horseId)
    .maybeSingle();

  if (!existingHorse) {
    redirectWithNotice("/admin/horses", "未找到要编辑的 Horse。");
  }

  const updatePayload: Record<string, unknown> = { ...horse };
  if (!existingHorse.owner_id) {
    updatePayload.owner_id = optionalId(formData, "owner_id");
  }

  const { error } = await supabase
    .from("horses")
    .update(updatePayload)
    .eq("id", horseId);

  if (error) {
    redirectWithNotice(`/admin/horses/${horseId}`, "Horse 更新失败。已归属 Horse 不能直接转移 Owner。");
  }

  revalidatePath("/admin/horses");
  revalidatePath(`/admin/horses/${horseId}`);
  revalidatePath("/horses");
  revalidatePath(`/horses/${horseId}`);
  redirectWithNotice(`/admin/horses/${horseId}`, "Horse 资料已更新。");
}

export async function addHorseFactor(horseId: string, formData: FormData) {
  const { supabase } = await requireGM();
  const factorKind = requiredText(formData, "factor_kind");
  const factorName = requiredText(formData, "factor_name");

  if (!factorName || (factorKind !== "SIRE" && factorKind !== "MARE")) {
    redirectWithNotice(`/admin/horses/${horseId}`, "请选择 SIRE 或 MARE，并填写 Factor 名称。");
  }

  const { count } = await supabase
    .from("horse_factors")
    .select("id", { count: "exact", head: true })
    .eq("horse_id", horseId)
    .eq("factor_kind", factorKind);

  if ((count ?? 0) >= 2) {
    redirectWithNotice(`/admin/horses/${horseId}`, `${factorKind} 最多只能记录 2 个 Factor。`);
  }

  const { error } = await supabase.from("horse_factors").insert({
    horse_id: horseId,
    factor_kind: factorKind,
    factor_name: factorName,
  });

  if (error) {
    redirectWithNotice(`/admin/horses/${horseId}`, "Factor 新增失败；数据库仍会拒绝每类第 3 个 Factor。");
  }

  revalidatePath(`/admin/horses/${horseId}`);
  revalidatePath(`/horses/${horseId}`);
  redirectWithNotice(`/admin/horses/${horseId}`, "Horse Factor 已新增。");
}

export async function deleteHorseFactor(horseId: string, factorId: string) {
  const { supabase } = await requireGM();
  const { error } = await supabase
    .from("horse_factors")
    .delete()
    .eq("id", factorId)
    .eq("horse_id", horseId);

  if (error) {
    redirectWithNotice(`/admin/horses/${horseId}`, "Factor 删除失败。");
  }

  revalidatePath(`/admin/horses/${horseId}`);
  revalidatePath(`/horses/${horseId}`);
  redirectWithNotice(`/admin/horses/${horseId}`, "Horse Factor 已删除。");
}

export async function saveGameState(formData: FormData) {
  const { supabase, user } = await requireGM();
  const year = positiveInteger(formData, "current_wp_year");
  const month = positiveInteger(formData, "current_wp_month");
  const week = positiveInteger(formData, "current_wp_week");

  if (!year || !month || !week || Number(month) > 12 || Number(week) > 5) {
    redirectWithNotice("/admin/game-state", "请填写有效的 WP 年、月（1-12）和周（1-5）。");
  }

  const { data: current } = await supabase.from("game_state").select("id").maybeSingle();
  const payload = {
    current_wp_year: year,
    current_wp_month: month,
    current_wp_week: week,
    updated_by_user_id: user.id,
  };

  const { error } = current
    ? await supabase.from("game_state").update(payload).eq("id", true)
    : await supabase.from("game_state").insert({ id: true, ...payload });

  if (error) {
    redirectWithNotice("/admin/game-state", "游戏时间保存失败。");
  }

  revalidatePath("/");
  revalidatePath("/admin/game-state");
  redirectWithNotice("/admin/game-state", "当前 Winning Post 时间已保存。");
}
