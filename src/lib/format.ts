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
