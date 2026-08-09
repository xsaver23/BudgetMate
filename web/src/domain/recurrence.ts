import { isDateOnly, localDateKey, localNoonISOString } from "./dates";
import type { BudgetTransaction } from "./types";

export type MonthlyRecurrence = {
  until?: string;
};

export function parseMonthlyRecurrence(rule?: string | null): MonthlyRecurrence | undefined {
  if (rule === "monthly") {
    return {};
  }

  const until = /^(?:monthly)\|until=(\d{4}-\d{2}-\d{2})$/.exec(rule ?? "")?.[1];
  return until && isDateOnly(until) ? { until } : undefined;
}

export function buildMonthlyRecurrence(enabled: boolean, until?: string): string | undefined {
  if (!enabled) {
    return undefined;
  }
  if (!until) {
    return "monthly";
  }
  return isDateOnly(until) ? `monthly|until=${until}` : undefined;
}

export function previousLocalDate(dateOnly: string): string | undefined {
  const noon = localNoonISOString(dateOnly);
  if (!noon) {
    return undefined;
  }

  const date = new Date(noon);
  date.setDate(date.getDate() - 1);
  return localDateKey(date);
}

export function activeRecurringExpenses(
  transactions: BudgetTransaction[],
  today: string = localDateKey()
): BudgetTransaction[] {
  return transactions
    .filter((transaction) => {
      if (transaction.type !== "expense") {
        return false;
      }
      const recurrence = parseMonthlyRecurrence(transaction.recurrenceRule);
      return !!recurrence && (!recurrence.until || recurrence.until >= today);
    })
    .sort((left, right) => {
      const leftDate = new Date(left.date).getTime();
      const rightDate = new Date(right.date).getTime();
      if (leftDate !== rightDate) {
        return leftDate - rightDate;
      }
      return left.title.localeCompare(right.title);
    });
}
