import { isInternalBudgetKey, isMonthBudgetKey, monthBudgetKey } from "./budgetMath";
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
const builtInExpenseCategoryIds = new Set(expenseCategories.map((category) => category.id));
export const hiddenCategoryPrefix = "__hiddenCategory__";

export function hiddenCategoryKey(categoryId: string): string {
  return `${hiddenCategoryPrefix}${categoryId}`;
}

function monthBudgetCategory(key: string): { month: string; category: string } | undefined {
  if (!isMonthBudgetKey(key)) {
    return undefined;
  }

  const value = key.slice("__monthBudget__:".length);
  const separatorIndex = value.indexOf(":");
  if (separatorIndex < 0) {
    return undefined;
  }

  const month = value.slice(0, separatorIndex);
  const category = value.slice(separatorIndex + 1);
  return month && category ? { month, category } : undefined;
}

function categoryIdFromBudgetKey(key: string): string | undefined {
  const scoped = monthBudgetCategory(key);
  if (scoped) return scoped.category;

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

export function categoryIdFromDisplayName(displayName: string): string | undefined {
  const words = displayName
    .trim()
    .split(/[^\p{L}\p{N}]+/u)
    .filter(Boolean)
    .map((word) => word.toLowerCase());

  if (words.length === 0) {
    return undefined;
  }

  return [words[0], ...words.slice(1).map((word) => `${word[0].toUpperCase()}${word.slice(1)}`)].join("");
}

type GraphemeSegmenter = {
  segment(value: string): Iterable<{ segment: string }>;
};

type IntlWithSegmenter = typeof Intl & {
  Segmenter?: new (
    locales?: string | string[],
    options?: { granularity: "grapheme" }
  ) => GraphemeSegmenter;
};

export function isSingleEmoji(value: string): boolean {
  const trimmed = value.trim();
  const Segmenter = (Intl as IntlWithSegmenter).Segmenter;
  if (!trimmed || !Segmenter) {
    return false;
  }

  const graphemes = [...new Segmenter(undefined, { granularity: "grapheme" }).segment(trimmed)].map(
    (part) => part.segment
  );
  if (graphemes.length !== 1) {
    return false;
  }

  const grapheme = graphemes[0];
  if (!/\p{Emoji}/u.test(grapheme)) {
    return false;
  }

  if (/^[0-9#*]\uFE0F?\u20E3$/u.test(grapheme)) {
    return true;
  }

  return Array.from(grapheme).some((scalar) => {
    const codePoint = scalar.codePointAt(0) ?? 0;
    return /\p{Emoji_Presentation}/u.test(scalar) ||
      (codePoint > 0x238c && /\p{Emoji}/u.test(scalar));
  });
}

export function normalizedCategoryEmoji(value?: string): string | undefined {
  const trimmed = value?.trim() ?? "";
  return trimmed && isSingleEmoji(trimmed) ? trimmed : undefined;
}

function copySettings(settings: BudgetSettings): BudgetSettings {
  return {
    ...settings,
    categoryBudgets: { ...settings.categoryBudgets },
    categoryEmojis: { ...settings.categoryEmojis }
  };
}

export function addCategorySettings(
  settings: BudgetSettings,
  categoryId: string,
  emoji?: string
): BudgetSettings {
  const next = copySettings(settings);
  next.categoryBudgets[categoryId] = 0;
  delete next.categoryBudgets[hiddenCategoryKey(categoryId)];
  delete next.categoryEmojis[categoryId];
  const normalizedEmoji = normalizedCategoryEmoji(emoji);
  if (normalizedEmoji) {
    next.categoryEmojis[categoryId] = normalizedEmoji;
  }
  return next;
}

export function updateCategoryEmojiSettings(
  settings: BudgetSettings,
  categoryId: string,
  emoji?: string
): BudgetSettings {
  const next = copySettings(settings);
  delete next.categoryEmojis[categoryId];
  const normalizedEmoji = normalizedCategoryEmoji(emoji);
  if (normalizedEmoji) {
    next.categoryEmojis[categoryId] = normalizedEmoji;
  }
  return next;
}

export function renameCategorySettings(
  settings: BudgetSettings,
  oldCategoryId: string,
  newCategoryId: string,
  emoji?: string
): BudgetSettings {
  const next = copySettings(settings);
  next.categoryBudgets[newCategoryId] = next.categoryBudgets[oldCategoryId] ?? 0;
  delete next.categoryBudgets[oldCategoryId];

  for (const [key, amount] of Object.entries(settings.categoryBudgets)) {
    const scoped = monthBudgetCategory(key);
    if (!scoped || scoped.category !== oldCategoryId) {
      continue;
    }
    next.categoryBudgets[monthBudgetKey(scoped.month, newCategoryId)] = amount;
    delete next.categoryBudgets[key];
  }

  const currentEmoji = normalizedCategoryEmoji(emoji) ?? settings.categoryEmojis[oldCategoryId];
  delete next.categoryEmojis[oldCategoryId];
  delete next.categoryEmojis[newCategoryId];
  if (currentEmoji) {
    next.categoryEmojis[newCategoryId] = currentEmoji;
  }

  if (builtInExpenseCategoryIds.has(oldCategoryId)) {
    next.categoryBudgets[hiddenCategoryKey(oldCategoryId)] = 1;
  }
  delete next.categoryBudgets[hiddenCategoryKey(newCategoryId)];
  return next;
}

export function removeCategorySettings(settings: BudgetSettings, categoryId: string): BudgetSettings {
  const next = copySettings(settings);
  if (builtInExpenseCategoryIds.has(categoryId)) {
    next.categoryBudgets[categoryId] = 0;
    next.categoryBudgets[hiddenCategoryKey(categoryId)] = 1;
  } else {
    delete next.categoryBudgets[categoryId];
    delete next.categoryBudgets[hiddenCategoryKey(categoryId)];
  }
  delete next.categoryEmojis[categoryId];
  for (const key of Object.keys(next.categoryBudgets)) {
    if (monthBudgetCategory(key)?.category === categoryId) {
      delete next.categoryBudgets[key];
    }
  }
  return next;
}

export function unhideCategorySettings(settings: BudgetSettings, categoryId: string): BudgetSettings {
  const next = copySettings(settings);
  delete next.categoryBudgets[hiddenCategoryKey(categoryId)];
  return next;
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
  rent: "#6B9A63",
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
