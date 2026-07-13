const dateOnlyPattern = /^(\d{4})-(\d{2})-(\d{2})$/;

export function localDateKey(date: Date = new Date()): string {
  if (Number.isNaN(date.getTime())) {
    return "";
  }

  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const day = String(date.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

export function localMonthKey(date: Date = new Date()): string {
  if (Number.isNaN(date.getTime())) {
    return "";
  }

  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}`;
}

export function localNoonISOString(dateOnly: string): string | undefined {
  const match = dateOnlyPattern.exec(dateOnly);
  if (!match) {
    return undefined;
  }

  const year = Number(match[1]);
  const monthIndex = Number(match[2]) - 1;
  const day = Number(match[3]);
  const date = new Date(year, monthIndex, day, 12, 0, 0, 0);

  if (
    date.getFullYear() !== year ||
    date.getMonth() !== monthIndex ||
    date.getDate() !== day
  ) {
    return undefined;
  }

  return date.toISOString();
}

export function isDateOnly(value: string | null | undefined): value is string {
  return !!value && localNoonISOString(value) !== undefined;
}
