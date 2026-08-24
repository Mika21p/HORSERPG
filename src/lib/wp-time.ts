export type WpTime = {
  year: number;
  month: number;
  week: number;
};

export function nextWpTime(current: WpTime): WpTime {
  if (current.week < 5) {
    return { ...current, week: current.week + 1 };
  }
  if (current.month < 12) {
    return { year: current.year, month: current.month + 1, week: 1 };
  }
  return { year: current.year + 1, month: 1, week: 1 };
}

export function wpTimeOrder(time: WpTime) {
  return time.year * 100 + time.month * 10 + time.week;
}
