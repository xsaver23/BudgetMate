import type { BudgetSettings } from "./types";

export function defaultBudgetSettings(budgetId: string): BudgetSettings {
  return {
    budgetId,
    currencyCode: "USD",
    appearance: "system",
    categoryBudgets: {},
    categoryEmojis: {}
  };
}
