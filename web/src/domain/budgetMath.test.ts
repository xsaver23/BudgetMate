import { describe, expect, it } from "vitest";
import { monthKey, transactionsForMonth } from "./budgetMath";
import { localDateKey, localNoonISOString } from "./dates";
import type { BudgetTransaction } from "./types";

function transaction(
  dateOnly: string,
  recurrenceRule?: string,
  id = "00000000-0000-4000-8000-000000000001"
): BudgetTransaction {
  return {
    id,
    budgetId: "00000000-0000-4000-8000-000000000002",
    userId: "00000000-0000-4000-8000-000000000003",
    title: "Rent",
    amount: 1200,
    type: "expense",
    category: "rent",
    paymentMethod: "card",
    createdByMemberId: "00000000-0000-4000-8000-000000000004",
    date: localNoonISOString(dateOnly)!,
    createdAt: localNoonISOString(dateOnly)!,
    recurrenceRule,
    splits: []
  };
}

describe("local calendar keys", () => {
  it("does not use tomorrow's UTC date near a local-day boundary", () => {
    const lateLocalEvening = new Date(2026, 6, 11, 22, 30, 0, 0);

    expect(localDateKey(lateLocalEvening)).toBe("2026-07-11");
    expect(monthKey(lateLocalEvening)).toBe("2026-07");
  });

  it("materializes date-only values at local noon", () => {
    const materialized = new Date(localNoonISOString("2026-07-11")!);
    expect(localDateKey(materialized)).toBe("2026-07-11");
    expect(materialized.getHours()).toBe(12);
    expect(localNoonISOString("2026-02-30")).toBeUndefined();
  });
});

describe("monthly recurrence", () => {
  it("clamps end-of-month occurrences while preserving the source transaction", () => {
    const source = transaction("2028-01-31", "monthly");
    const [february] = transactionsForMonth([source], "2028-02");

    expect(localDateKey(new Date(february.date))).toBe("2028-02-29");
    expect(february.id).toBe(source.id);
    expect(source.date).toBe(localNoonISOString("2028-01-31"));
  });

  it("does not generate occurrences before the source month", () => {
    expect(transactionsForMonth([transaction("2026-07-11", "monthly")], "2026-06")).toEqual([]);
  });

  it("treats the recurrence end date as inclusive", () => {
    const source = transaction("2026-01-31", "monthly|until=2026-03-31");

    expect(transactionsForMonth([source], "2026-03")).toHaveLength(1);
    expect(transactionsForMonth([source], "2026-04")).toEqual([]);
  });

  it("does not expand non-recurring transactions", () => {
    expect(transactionsForMonth([transaction("2026-01-15")], "2026-02")).toEqual([]);
  });
});
