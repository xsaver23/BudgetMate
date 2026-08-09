import { describe, expect, it } from "vitest";
import { activeRecurringExpenses, buildMonthlyRecurrence, parseMonthlyRecurrence, previousLocalDate } from "./recurrence";
import type { BudgetTransaction } from "./types";

const transaction = (overrides: Partial<BudgetTransaction>): BudgetTransaction => ({
  id: "transaction",
  budgetId: "budget",
  userId: "user",
  title: "Expense",
  amount: 10,
  type: "expense",
  category: "other",
  createdByMemberId: "member",
  date: "2026-01-01T12:00:00.000Z",
  createdAt: "2026-01-01T12:00:00.000Z",
  recurrenceRule: "monthly",
  splits: [],
  ...overrides
});

describe("monthly recurrence", () => {
  it("parses and builds the canonical monthly rules", () => {
    expect(parseMonthlyRecurrence("monthly")).toEqual({});
    expect(parseMonthlyRecurrence("monthly|until=2026-03-31")).toEqual({ until: "2026-03-31" });
    expect(parseMonthlyRecurrence("monthly|until=2026-02-30")).toBeUndefined();
    expect(parseMonthlyRecurrence("weekly")).toBeUndefined();

    expect(buildMonthlyRecurrence(true)).toBe("monthly");
    expect(buildMonthlyRecurrence(true, "2026-03-31")).toBe("monthly|until=2026-03-31");
    expect(buildMonthlyRecurrence(false, "2026-03-31")).toBeUndefined();
    expect(buildMonthlyRecurrence(true, "2026-02-30")).toBeUndefined();
  });

  it("finds the previous local date across month and year boundaries", () => {
    expect(previousLocalDate("2026-03-01")).toBe("2026-02-28");
    expect(previousLocalDate("2026-01-01")).toBe("2025-12-31");
    expect(previousLocalDate("2028-03-01")).toBe("2028-02-29");
  });

  it("keeps active stored monthly expense sources sorted by start date and title", () => {
    const active = transaction({ id: "active", title: "Zed", date: "2026-03-01T12:00:00.000Z" });
    const sameDate = transaction({ id: "same-date", title: "Alpha", date: "2026-03-01T12:00:00.000Z" });
    const expired = transaction({ id: "expired", recurrenceRule: "monthly|until=2026-02-28" });
    const income = transaction({ id: "income", type: "income" });

    expect(activeRecurringExpenses([active, expired, income, sameDate], "2026-03-15")).toEqual([sameDate, active]);
  });
});
