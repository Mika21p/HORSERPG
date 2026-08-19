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
