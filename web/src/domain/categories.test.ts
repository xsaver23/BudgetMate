import { describe, expect, it } from "vitest";
import { visibleExpenseCategories } from "./categories";
import type { BudgetSettings, BudgetTransaction } from "./types";

const settings: BudgetSettings = {
  budgetId: "budget",
  currencyCode: "CAD",
  appearance: "system",
  categoryBudgets: {
    groceries: 0,
    "__hiddenCategory__groceries": 1,
    petCare: 80,
    "__monthBudget__:2026-07:homeOffice": 120
  },
  categoryEmojis: { petCare: "🐕" }
};

const historicalCustomTransaction = {
  id: "transaction",
  budgetId: "budget",
  userId: "user",
  title: "Tailor",
  amount: 20,
  type: "expense",
  category: "clothingAlterations",
  createdByMemberId: "member",
  date: "2026-07-11T16:00:00.000Z",
  createdAt: "2026-07-11T16:00:00.000Z",
  splits: []
} satisfies BudgetTransaction;

describe("visibleExpenseCategories", () => {
  it("honors hidden markers and includes synced custom categories", () => {
    const ids = visibleExpenseCategories(settings, [historicalCustomTransaction]).map((category) => category.id);

    expect(ids).not.toContain("groceries");
    expect(ids).toContain("petCare");
    expect(ids).toContain("homeOffice");
    expect(ids).toContain("clothingAlterations");
  });
});
