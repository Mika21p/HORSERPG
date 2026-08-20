export function formatGameMoney(value: bigint | number | string | null | undefined) {
  if (value === null || value === undefined) {
    return "—";
  }

  try {
    return `¥${BigInt(value).toLocaleString("zh-CN")}`;
  } catch {
    return "¥0";
  }
}

export function formatDateTime(value: string | null | undefined) {
  if (!value) {
    return "—";
  }

  return new Intl.DateTimeFormat("zh-CN", {
    dateStyle: "medium",
    timeStyle: "short",
    timeZone: "Asia/Shanghai",
  }).format(new Date(value));
}

function chinaDateTimeParts(value: string) {
  const parts = new Intl.DateTimeFormat("en-CA", {
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    hourCycle: "h23",
    timeZone: "Asia/Shanghai",
  }).formatToParts(new Date(value));

  return new Map(parts.map((part) => [part.type, part.value]));
}

export function toChinaDateInput(value: string) {
  const parts = chinaDateTimeParts(value);
  return `${parts.get("year")}-${parts.get("month")}-${parts.get("day")}`;
}

export function toChinaTimeInput(value: string) {
  const parts = chinaDateTimeParts(value);
  return `${parts.get("hour")}:${parts.get("minute")}`;
}

export function toUtcDateTimeInput(value: string) {
  return new Date(value).toISOString().slice(0, 16);
}

export function formatFoalTradeSessionStatus(status: string) {
  const labels: Record<string, string> = {
    DRAFT: "草稿",
    OPEN: "开放中",
    CLOSED: "已关闭",
    REVIEWING: "结算审核中",
    SETTLED: "已结算",
  };

  return labels[status] ?? status;
}

export function formatFoalTradeLotStatus(status: string) {
  const labels: Record<string, string> = {
    LISTED: "待结算",
    SOLD: "已成交",
    UNSOLD: "未成交",
  };

  return labels[status] ?? status;
}

export function formatWpTime(
  year: number | string | null | undefined,
  month: number | string | null | undefined,
  week: number | string | null | undefined,
) {
  if (year === null || year === undefined || month === null || month === undefined || week === null || week === undefined) {
    return "—";
  }

  return `WP ${year} 年 ${month} 月 Week ${week}`;
}

export function formatRaceKind(kind: string | null | undefined) {
  const labels: Record<string, string> = {
    CATALOG: "固定比赛",
    MAIDEN: "未胜利赛",
    CONDITION: "条件赛",
    OTHER: "其他比赛",
  };

  return kind ? labels[kind] ?? kind : "—";
}

export function formatRaceGrade(grade: string | null | undefined) {
  return grade || "未分级";
}

export function formatHorseName(horse: {
  translated_name?: string | null;
  foal_name?: string | null;
  horse_number?: number | string | null;
} | null | undefined) {
  if (!horse) return "Horse";
  return horse.translated_name || horse.foal_name || (horse.horse_number ? `Horse #${horse.horse_number}` : "Horse");
}

export function formatRaceResultStatus(status: string | null | undefined) {
  const labels: Record<string, string> = {
    CONFIRMED: "有效赛果",
    VOIDED: "已作废",
  };

  return status ? labels[status] ?? status : "—";
}

export function formatRaceEntryRequestStatus(status: string | null | undefined) {
  const labels: Record<string, string> = {
    PENDING: "等待 GM 审核",
    CONFIRMED: "已确认",
    REJECTED: "已拒绝",
    WITHDRAWN: "已撤回",
  };

  return status ? labels[status] ?? status : "—";
}
