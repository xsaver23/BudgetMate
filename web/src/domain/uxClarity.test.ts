import { describe, expect, it } from "vitest";
import { monthBudgetKey, monthlyBudget, selectedCategoryBudgets } from "./budgetMath";
import { memberFilterLabels, organizeCategoryBudgetRows } from "./uxClarity";
import type { BudgetSettings } from "./types";

describe("member filter labels", () => {
  it("uses the shortest unique name prefix and keeps the full name", () => {
    const labels = memberFilterLabels([
      { id: "owner", displayName: "Gate C Owner", email: "owner@example.com" },
      { id: "member", displayName: "Gate C Member", email: "member@example.com" },
      { id: "mina", displayName: "Mina Hart", email: "mina@example.com" }
    ]);

    expect(labels.map((label) => label.displayLabel)).toEqual(["Gate C Owner", "Gate C Member", "Mina"]);
    expect(labels.map((label) => label.fullName)).toEqual(["Gate C Owner", "Gate C Member", "Mina Hart"]);
    expect(new Set(labels.map((label) => label.displayLabel)).size).toBe(labels.length);
  });

  it("does not collapse members with the same full name", () => {
    const labels = memberFilterLabels([
      { id: "one", displayName: "Taylor Lee", email: "one@example.com" },
      { id: "two", displayName: "Taylor Lee", email: "two@example.com" }
    ]);

    expect(labels.map((label) => label.displayLabel)).toEqual([
      "Taylor Lee · one@example.com",
      "Taylor Lee · two@example.com"
    ]);
    expect(new Set(labels.map((label) => label.displayLabel)).size).toBe(2);
  });
});

describe("category budget disclosure", () => {
  it("puts budgeted categories first and leaves unused categories for the collapsed disclosure", () => {
    const rows = [
      { id: "spending-only", budget: 0, spent: 50 },
      { id: "rent", budget: 1200, spent: 0 },
      { id: "unused", budget: 0, spent: 0 },
      { id: "food", budget: 300, spent: 100 }
    ];

    const { visibleRows, unbudgetedRows } = organizeCategoryBudgetRows(rows);

    expect(visibleRows.map((row) => row.id)).toEqual(["rent", "food", "spending-only"]);
    expect(unbudgetedRows.map((row) => row.id)).toEqual(["unused"]);
  });

  it("keeps category budgets and totals scoped to the selected month", () => {
    const settings: BudgetSettings = {
      budgetId: "budget",
      currencyCode: "CAD",
      appearance: "system",
      categoryBudgets: {
        [monthBudgetKey("2026-07", "rent")]: 800,
        [monthBudgetKey("2026-08", "rent")]: 1000,
        [monthBudgetKey("2026-08", "food")]: 300
      },
      categoryEmojis: {}
    };

    expect(selectedCategoryBudgets(settings, "2026-07")).toEqual({ rent: 800 });
    expect(monthlyBudget(settings, "2026-07")).toBe(800);
    expect(selectedCategoryBudgets(settings, "2026-08")).toEqual({ rent: 1000, food: 300 });
    expect(monthlyBudget(settings, "2026-08")).toBe(1300);
  });
});
