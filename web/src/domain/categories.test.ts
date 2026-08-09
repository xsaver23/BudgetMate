import { describe, expect, it } from "vitest";
import {
  addCategorySettings,
  categoryIdFromDisplayName,
  isSingleEmoji,
  removeCategorySettings,
  renameCategorySettings,
  unhideCategorySettings,
  visibleExpenseCategories
} from "./categories";
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

describe("category management metadata", () => {
  it("canonicalizes display names to lower camelCase", () => {
    expect(categoryIdFromDisplayName("  Pet-care & Supplies ")).toBe("petCareSupplies");
    expect(categoryIdFromDisplayName("Student loans")).toBe("studentLoans");
    expect(categoryIdFromDisplayName(" --- ")).toBeUndefined();
  });

  it("accepts one emoji grapheme and rejects text or multiple graphemes", () => {
    expect(isSingleEmoji("👨‍👩‍👧‍👦")).toBe(true);
    expect(isSingleEmoji("🇨🇦")).toBe(true);
    expect(isSingleEmoji("🐕🐕")).toBe(false);
    expect(isSingleEmoji("dog")).toBe(false);
  });

  it("moves scoped metadata and removes category metadata without mutating input", () => {
    const renamed = renameCategorySettings(settings, "petCare", "homeOffice", "🏠");

    expect(renamed.categoryBudgets).toEqual({
      groceries: 0,
      "__hiddenCategory__groceries": 1,
      homeOffice: 80,
      "__monthBudget__:2026-07:homeOffice": 120
    });
    expect(renamed.categoryEmojis).toEqual({ homeOffice: "🏠" });
    expect(settings.categoryBudgets.petCare).toBe(80);

    const removedBuiltIn = removeCategorySettings(settings, "groceries");
    expect(removedBuiltIn.categoryBudgets).toEqual({
      "__hiddenCategory__groceries": 1,
      groceries: 0,
      petCare: 80,
      "__monthBudget__:2026-07:homeOffice": 120
    });
    expect(removedBuiltIn.categoryEmojis).toEqual({ petCare: "🐕" });

    const added = addCategorySettings(removedBuiltIn, "homeOffice", "🏠");
    expect(added.categoryBudgets.homeOffice).toBe(0);
    expect(added.categoryEmojis.homeOffice).toBe("🏠");
    expect(unhideCategorySettings(removedBuiltIn, "groceries").categoryBudgets).toEqual({
      groceries: 0,
      petCare: 80,
      "__monthBudget__:2026-07:homeOffice": 120
    });
  });
});
