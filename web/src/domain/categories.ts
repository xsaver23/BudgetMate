import { isInternalBudgetKey } from "./budgetMath";
import type { BudgetSettings, BudgetTransaction } from "./types";

export interface CategoryDefinition {
  id: string;
  name: string;
}

export const expenseCategories: CategoryDefinition[] = [
  { id: "rent", name: "Rent" },
  { id: "bills", name: "Bills" },
  { id: "studentLoans", name: "Student loans" },
  { id: "subscription", name: "Subscription" },
  { id: "food", name: "Food" },
  { id: "groceries", name: "Groceries" },
  { id: "health", name: "Health" },
  { id: "household", name: "Household" },
  { id: "gas", name: "Gas" },
  { id: "parking", name: "Parking" },
  { id: "transportation", name: "Transportation" },
  { id: "shopping", name: "Shopping" },
  { id: "restaurant", name: "Restaurant" },
  { id: "date", name: "Date" },
  { id: "vacation", name: "Vacation" },
  { id: "entertainment", name: "Entertainment" },
  { id: "gift", name: "Gift" },
  { id: "other", name: "Other" }
];

export const incomeCategories: CategoryDefinition[] = [
  { id: "gift", name: "Gift" },
  { id: "refund", name: "Refund" },
  { id: "work", name: "Work" },
  { id: "eTransfer", name: "E-transfer" },
  { id: "other", name: "Other" }
];

const allCategories = new Map(
  [...expenseCategories, ...incomeCategories].map((category) => [category.id, category.name])
);

const builtInCategoryIds = new Set(allCategories.keys());
const hiddenCategoryPrefix = "__hiddenCategory__";
const monthBudgetPrefix = "__monthBudget__:";

function categoryIdFromBudgetKey(key: string): string | undefined {
  if (key.startsWith(monthBudgetPrefix)) {
    const scopedValue = key.slice(monthBudgetPrefix.length);
    const separatorIndex = scopedValue.indexOf(":");
    return separatorIndex >= 0 ? scopedValue.slice(separatorIndex + 1) || undefined : undefined;
  }

  return isInternalBudgetKey(key) ? undefined : key;
}

export function hiddenExpenseCategoryIds(settings: BudgetSettings): Set<string> {
  return new Set(
    Object.keys(settings.categoryBudgets)
      .filter((key) => key.startsWith(hiddenCategoryPrefix))
      .map((key) => key.slice(hiddenCategoryPrefix.length))
      .filter(Boolean)
  );
}

export function visibleExpenseCategories(
  settings: BudgetSettings,
  transactions: BudgetTransaction[] = []
): CategoryDefinition[] {
  const hiddenIds = hiddenExpenseCategoryIds(settings);
  const builtIns = expenseCategories.filter((category) => !hiddenIds.has(category.id));
  const customIds = new Set<string>();

  Object.keys(settings.categoryBudgets).forEach((key) => {
    const categoryId = categoryIdFromBudgetKey(key);
    if (categoryId) customIds.add(categoryId);
  });
  Object.keys(settings.categoryEmojis).forEach((categoryId) => customIds.add(categoryId));
  transactions
    .filter((transaction) => transaction.type === "expense")
    .forEach((transaction) => customIds.add(transaction.category));

  const custom = Array.from(customIds)
    .filter((categoryId) => !builtInCategoryIds.has(categoryId) && !hiddenIds.has(categoryId))
    .map((categoryId) => ({ id: categoryId, name: categoryName(categoryId) }))
    .sort((left, right) => left.name.localeCompare(right.name, undefined, { sensitivity: "base" }));

  return [...builtIns, ...custom];
}

const categoryColors: Record<string, string> = {
  rent: "#1E3A2B",
  bills: "#E7B84B",
  studentLoans: "#5E5D50",
  subscription: "#3F9E5E",
  food: "#3F9E5E",
  groceries: "#3F9E5E",
  health: "#3B82C4",
  household: "#6F6D61",
  gas: "#E7B84B",
  parking: "#7A5A14",
  transportation: "#3F9E5E",
  shopping: "#E7B84B",
  restaurant: "#D6694C",
  date: "#D6694C",
  vacation: "#3B82C4",
  entertainment: "#3B82C4",
  gift: "#E7B84B",
  refund: "#3F9E5E",
  work: "#3F9E5E",
  eTransfer: "#3F9E5E",
  other: "#E7B84B"
};

function relativeLuminance(hex: string): number {
  const normalized = hex.replace("#", "");
  if (normalized.length !== 6) {
    return 0.5;
  }

  const channels = [0, 2, 4].map((offset) => parseInt(normalized.slice(offset, offset + 2), 16) / 255);
  const linear = channels.map((channel) =>
    channel <= 0.04045 ? channel / 12.92 : Math.pow((channel + 0.055) / 1.055, 2.4)
  );
  return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2];
}

export function contrastTextColor(background: string): string {
  const luminance = relativeLuminance(background);
  const lightLuminance = relativeLuminance("#FFFDF8");
  const darkLuminance = relativeLuminance("#11150F");
  const lightContrast = (Math.max(luminance, lightLuminance) + 0.05) / (Math.min(luminance, lightLuminance) + 0.05);
  const darkContrast = (Math.max(luminance, darkLuminance) + 0.05) / (Math.min(luminance, darkLuminance) + 0.05);
  return lightContrast >= darkContrast ? "#FFFDF8" : "#11150F";
}

export function categoryName(id: string): string {
  if (allCategories.has(id)) {
    return allCategories.get(id) as string;
  }

  return id
    .replace(/([a-z0-9])([A-Z])/g, "$1 $2")
    .replace(/[_-]/g, " ")
    .replace(/^./, (char) => char.toUpperCase());
}

export function categoryColor(id: string): string {
  return categoryColors[id] ?? "#E7B84B";
}

export function categoryTextColor(id: string): string {
  return contrastTextColor(categoryColor(id));
}
