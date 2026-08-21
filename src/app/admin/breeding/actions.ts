"use server";

import { revalidatePath } from "next/cache";

import { requireGM } from "@/lib/auth/session";

type DatabaseError = { code?: string; message?: string } | null;

export type BreedingMutationResult =
  | { ok: true; notice: string }
  | { ok: false; message: string; restartRequired?: boolean };

export type FoalCreationResult =
  | {
    ok: true;
    notice: string;
    horse: {
      id: string;
      horseNumber: string;
      foalName: string;
      translatedName: string | null;
      sex: string;
      coatColor: string;
      sireName: string;
      sireLine: string;
      damName: string | null;
      broodmareSireName: string;
    };
  }
  | { ok: false; message: string; restartRequired?: boolean };

export type FoalParentSource = "INTERNAL" | "REFERENCE" | "MANUAL";

export type CreateFoalInput = {
  requestId: string;
  horseNumber: string;
  birthYear: string;
  foalName: string;
  nameKatakana: string;
  translatedName: string;
  sex: string;
  coatColor: string;
  sireSourceType: FoalParentSource;
  sireHorseId: string | null;
  sireReferenceId: string | null;
  manualSireName: string;
  manualSireLine: string;
  damSourceType: FoalParentSource;
  damHorseId: string | null;
  damReferenceId: string | null;
  manualDamName: string;
  manualBroodmareSireName: string;
};

const parentSourceValues = new Set<FoalParentSource>(["INTERNAL", "REFERENCE", "MANUAL"]);
const sexValues = new Set(["MALE", "FEMALE", "GELDING"]);
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function text(value: string | null | undefined) {
  return String(value ?? "").trim();
}

function nullableText(value: string | null | undefined) {
  return text(value) || null;
}

function isUuid(value: string | null | undefined) {
  return typeof value === "string" && uuidPattern.test(value);
}

function revalidateBreeding(horseId?: string) {
  revalidatePath("/admin/breeding");
  revalidatePath("/admin/horses");
  revalidatePath("/horses");
  if (horseId) {
    revalidatePath(`/admin/horses/${horseId}`);
    revalidatePath(`/horses/${horseId}`);
  }
}

function mutationError(error: DatabaseError, kind: "candidate" | "reference"): BreedingMutationResult {
  const message = error?.message?.toLowerCase() ?? "";

  if (message.includes("only a gm")) return { ok: false, message: "无权限执行此操作。" };
  if (message.includes("only a retired")) return { ok: false, message: "仅已退役 Horse 可加入繁育候选。" };
  if (message.includes("only male or female")) return { ok: false, message: "阉马不能加入繁育候选。" };
  if (message.includes("breeding candidate does not exist")) return { ok: false, message: "该 Horse 当前不是繁育候选，请刷新页面。" };
  if (message.includes("pedigree reference name is required")) return { ok: false, message: "请填写外部血统资料的标准名称。" };
  if (message.includes("pedigree reference sex")) return { ok: false, message: "外部血统资料的性别值无效。" };
  if (message.includes("pedigree reference horse does not exist")) return { ok: false, message: "该外部血统资料不存在或已被刷新。" };

  return {
    ok: false,
    message: kind === "candidate" ? "繁育候选操作失败，请刷新后重试。" : "外部血统资料操作失败，请刷新后重试。",
  };
}

function foalError(error: DatabaseError): FoalCreationResult {
  const message = error?.message?.toLowerCase() ?? "";

  if (message.includes("only a gm")) return { ok: false, message: "无权限创建幼驹。" };
  if (message.includes("request_id already exists with different facts")) {
    return { ok: false, message: "该创建请求已经用于另一组幼驹数据，请重新开始新建流程。", restartRequired: true };
  }
  if (message.includes("horse_number_key") || message.includes("duplicate key") || message.includes("horse number")) {
    return { ok: false, message: "该 Horse 编号已存在。请确认 Winning Post 编号后重试。" };
  }
  if (message.includes("internal sire")) return { ok: false, message: "选择的父马候选已不再有效，请重新选择。" };
  if (message.includes("internal dam")) return { ok: false, message: "选择的母马候选已不再有效，请重新选择。" };
  if (message.includes("reference sire")) return { ok: false, message: "外部父马资料不可用或缺少父系信息，请重新选择或改用手动输入。" };
  if (message.includes("reference dam")) return { ok: false, message: "外部母马资料不可用或缺少母父信息，请重新选择或改用手动输入。" };
  if (message.includes("manual sire")) return { ok: false, message: "手动父马必须填写父马名与父系。" };
  if (message.includes("manual dam")) return { ok: false, message: "手动母马必须填写母马名与母父名。" };
  if (message.includes("structured horse pedigree requires")) {
    return { ok: false, message: "系统错误：幼驹血统必须通过受控创建流程写入。请停止并联系维护者。" };
  }

  return { ok: false, message: "幼驹创建失败。数据库未接受本次写入，请检查资料后重试。" };
}

export async function activateBreedingCandidate(horseId: string, notes: string): Promise<BreedingMutationResult> {
  const { supabase } = await requireGM();
  if (!isUuid(horseId)) return { ok: false, message: "未找到有效的 Horse。" };

  const { error } = await supabase.rpc("activate_breeding_candidate", {
    p_horse_id: horseId,
    p_notes: nullableText(notes),
  });

  if (error) return mutationError(error, "candidate");
  revalidateBreeding(horseId);
  return { ok: true, notice: "Horse 已加入繁育候选；生命周期保持为 RETIRED。" };
}

export async function deactivateBreedingCandidate(horseId: string, reason: string): Promise<BreedingMutationResult> {
  const { supabase } = await requireGM();
  if (!isUuid(horseId)) return { ok: false, message: "未找到有效的 Horse。" };

  const { error } = await supabase.rpc("deactivate_breeding_candidate", {
    p_horse_id: horseId,
    p_reason: nullableText(reason),
  });

  if (error) return mutationError(error, "candidate");
  revalidateBreeding(horseId);
  return { ok: true, notice: "繁育候选已停用；Horse 继续保持 RETIRED。" };
}

export type PedigreeReferenceInput = {
  referenceId?: string;
  name: string;
  translatedName: string;
  sex: string;
  sireLine: string;
  sireName: string;
  damName: string;
  broodmareSireName: string;
  aliases: string[];
  notes: string;
};

function referencePayload(input: PedigreeReferenceInput) {
  const sex = text(input.sex);
  if (sex && !sexValues.has(sex)) return null;

  const aliases = Array.from(new Set(input.aliases.map((alias) => text(alias)).filter(Boolean)));
  return {
    p_name: nullableText(input.name),
    p_translated_name: nullableText(input.translatedName),
    p_sex: sex || null,
    p_sire_line: nullableText(input.sireLine),
    p_sire_name: nullableText(input.sireName),
    p_dam_name: nullableText(input.damName),
    p_broodmare_sire_name: nullableText(input.broodmareSireName),
    p_aliases: aliases,
    p_notes: nullableText(input.notes),
  };
}

export async function createPedigreeReference(input: PedigreeReferenceInput): Promise<BreedingMutationResult> {
  const { supabase } = await requireGM();
  const payload = referencePayload(input);
  if (!payload) return { ok: false, message: "外部血统资料的性别值无效。" };
  if (!payload.p_name) return { ok: false, message: "请填写外部血统资料的标准名称。" };

  const { error } = await supabase.rpc("create_pedigree_reference_horse", payload);
  if (error) return mutationError(error, "reference");
  revalidateBreeding();
  return { ok: true, notice: "外部血统资料已创建。它仅作为录入辅助，不会改变既有 Horse 快照。" };
}

export async function updatePedigreeReference(input: PedigreeReferenceInput): Promise<BreedingMutationResult> {
  const { supabase } = await requireGM();
  const payload = referencePayload(input);
  if (!isUuid(input.referenceId)) return { ok: false, message: "未找到要编辑的外部血统资料。" };
  if (!payload) return { ok: false, message: "外部血统资料的性别值无效。" };
  if (!payload.p_name) return { ok: false, message: "请填写外部血统资料的标准名称。" };

  const { error } = await supabase.rpc("update_pedigree_reference_horse", {
    p_reference_id: input.referenceId,
    ...payload,
  });
  if (error) return mutationError(error, "reference");
  revalidateBreeding();
  return { ok: true, notice: "外部血统资料已更新；既有 Horse 的历史血统快照不会改变。" };
}

export async function deactivatePedigreeReference(referenceId: string, reason: string): Promise<BreedingMutationResult> {
  const { supabase } = await requireGM();
  if (!isUuid(referenceId)) return { ok: false, message: "未找到要停用的外部血统资料。" };

  const { error } = await supabase.rpc("deactivate_pedigree_reference_horse", {
    p_reference_id: referenceId,
    p_reason: nullableText(reason),
  });
  if (error) return mutationError(error, "reference");
  revalidateBreeding();
  return { ok: true, notice: "外部血统资料已停用；它不会再出现在新建幼驹的默认选择中。" };
}

export async function createFoal(input: CreateFoalInput): Promise<FoalCreationResult> {
  const { supabase } = await requireGM();
  const horseNumber = text(input.horseNumber);
  const birthYear = text(input.birthYear);

  if (!isUuid(input.requestId)) return { ok: false, message: "创建请求无效，请重新开始新建幼驹。", restartRequired: true };
  if (!/^[1-9]\d*$/.test(horseNumber) || !/^[1-9]\d*$/.test(birthYear)) {
    return { ok: false, message: "Horse Number 与 WP 出生年份必须是正整数。" };
  }
  if (!text(input.foalName) || !text(input.coatColor) || !sexValues.has(text(input.sex))) {
    return { ok: false, message: "请完整填写幼驹名称、性别与毛色。" };
  }
  if (!parentSourceValues.has(input.sireSourceType) || !parentSourceValues.has(input.damSourceType)) {
    return { ok: false, message: "请分别选择父马与母马的血统来源。" };
  }

  const { data, error } = await supabase.rpc("create_foal", {
    p_request_id: input.requestId,
    p_horse_number: horseNumber,
    p_birth_year: Number(birthYear),
    p_foal_name: text(input.foalName),
    p_name_katakana: nullableText(input.nameKatakana),
    p_translated_name: nullableText(input.translatedName),
    p_sex: text(input.sex),
    p_coat_color: text(input.coatColor),
    p_sire_source_type: input.sireSourceType,
    p_sire_horse_id: input.sireSourceType === "INTERNAL" ? input.sireHorseId : null,
    p_sire_reference_id: input.sireSourceType === "REFERENCE" ? input.sireReferenceId : null,
    p_manual_sire_name: input.sireSourceType === "MANUAL" ? nullableText(input.manualSireName) : null,
    p_manual_sire_line: input.sireSourceType === "MANUAL" ? nullableText(input.manualSireLine) : null,
    p_dam_source_type: input.damSourceType,
    p_dam_horse_id: input.damSourceType === "INTERNAL" ? input.damHorseId : null,
    p_dam_reference_id: input.damSourceType === "REFERENCE" ? input.damReferenceId : null,
    p_manual_dam_name: input.damSourceType === "MANUAL" ? nullableText(input.manualDamName) : null,
    p_manual_broodmare_sire_name: input.damSourceType === "MANUAL" ? nullableText(input.manualBroodmareSireName) : null,
  });

  if (error || !data) return foalError(error);

  const horse = data as {
    id: string;
    horse_number: string | number;
    foal_name: string;
    translated_name: string | null;
    sex: string;
    coat_color: string;
    sire_name: string;
    sire_line: string;
    dam_name: string | null;
    broodmare_sire_name: string;
  };

  revalidateBreeding(horse.id);
  return {
    ok: true,
    notice: "幼驹已录入 HorseRPG；状态为 FOAL、无 Owner。",
    horse: {
      id: horse.id,
      horseNumber: String(horse.horse_number),
      foalName: horse.foal_name,
      translatedName: horse.translated_name,
      sex: horse.sex,
      coatColor: horse.coat_color,
      sireName: horse.sire_name,
      sireLine: horse.sire_line,
      damName: horse.dam_name,
      broodmareSireName: horse.broodmare_sire_name,
    },
  };
}
