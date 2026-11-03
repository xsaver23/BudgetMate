import { localDateKey } from "./dates";
import { amountFromMinorUnits, amountMinorUnits, formatMoney } from "./currency";
import type { BudgetMember } from "./types";

export interface MemberFilterLabel {
  memberId: string;
  fullName: string;
  displayLabel: string;
}

function normalizeWhitespace(value: string): string {
  return value.trim().replace(/\s+/g, " ");
}

function comparisonKey(value: string): string {
  return value.toLocaleLowerCase();
}

/** Use the shortest name prefix that distinguishes each member. */
export function memberFilterLabels(
  members: Pick<BudgetMember, "id" | "displayName" | "email">[]
): MemberFilterLabel[] {
  const names = members.map((member) => {
    const fullName = normalizeWhitespace(member.displayName) || "Unnamed member";
    return { fullName, words: fullName.split(" ") };
  });

  return members.map((member, index) => {
    const { fullName, words } = names[index];
    let displayLabel = fullName;

    for (let wordCount = 1; wordCount <= words.length; wordCount += 1) {
      const candidate = words.slice(0, wordCount).join(" ");
      const candidateKey = comparisonKey(candidate);
      const isUnique = names.every((other, otherIndex) => {
        if (otherIndex === index) {
          return true;
        }
        return comparisonKey(other.words.slice(0, wordCount).join(" ")) !== candidateKey;
      });

      if (isUnique) {
        displayLabel = candidate;
        break;
      }
    }

    const duplicateNameIndexes = names
      .map((other, otherIndex) => (comparisonKey(other.fullName) === comparisonKey(fullName) ? otherIndex : -1))
      .filter((otherIndex) => otherIndex >= 0);
    if (duplicateNameIndexes.length > 1) {
      const email = normalizeWhitespace(member.email ?? "");
      const emailIsUnique =
        !!email &&
        duplicateNameIndexes.filter(
          (otherIndex) => comparisonKey(normalizeWhitespace(members[otherIndex].email ?? "")) === comparisonKey(email)
        ).length === 1;
      displayLabel = emailIsUnique ? `${fullName} · ${email}` : `${fullName} #${duplicateNameIndexes.indexOf(index) + 1}`;
    }

    return { memberId: member.id, fullName, displayLabel };
  });
}

export function organizeCategoryBudgetRows<T extends { budget: number; spent: number }>(rows: T[]) {
  const budgetedRows = rows.filter((row) => row.budget > 0);
  const spendingWithoutBudgetRows = rows.filter((row) => row.budget <= 0 && row.spent > 0);
  const unbudgetedRows = rows.filter((row) => row.budget <= 0 && row.spent <= 0);

  return {
    visibleRows: [...budgetedRows, ...spendingWithoutBudgetRows],
    unbudgetedRows
  };
}

export function isUpcomingTransaction(transaction: { date: string }, today = localDateKey()): boolean {
  const date = localDateKey(new Date(transaction.date));
  return !!date && date > today;
}

export function categoryBudgetMinorUnits(value: string | number, currencyCode = "USD"): number | undefined {
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) return undefined;
  const raw = String(value).trim();
  const normalizedValue = Math.max(0, parsed);
  const candidate = raw === "" || parsed < 0 || !/^\d+(?:\.\d+)?$/.test(raw) ? String(normalizedValue) : raw;
  return amountMinorUnits(candidate, currencyCode);
}

function budgetMinorUnits(value: number, currencyCode: string): number {
  return categoryBudgetMinorUnits(value, currencyCode) ?? 0;
}

export function categoryBudgetStatus(
  spent: number,
  budget: number,
  currencyCode = "USD"
): "good" | "watch" | "at-limit" | "over" {
  const spentMinorUnits = budgetMinorUnits(spent, currencyCode);
  const budgetMinorUnitsValue = budgetMinorUnits(budget, currencyCode);
  if (budgetMinorUnitsValue <= 0) {
    return "good";
  }
  if (spentMinorUnits > budgetMinorUnitsValue) {
    return "over";
  }
  if (spentMinorUnits === budgetMinorUnitsValue) {
    return "at-limit";
  }
  return spentMinorUnits / budgetMinorUnitsValue >= 0.8 ? "watch" : "good";
}

export function categoryBudgetNeedsSave(value: string, currentBudget: number, currencyCode = "USD"): boolean {
  const nextMinorUnits = categoryBudgetMinorUnits(value, currencyCode);
  const currentMinorUnits = categoryBudgetMinorUnits(currentBudget, currencyCode);
  return nextMinorUnits !== undefined && currentMinorUnits !== undefined && nextMinorUnits !== currentMinorUnits;
}

export function categoryBudgetStatusLabel(spent: number, budget: number, currencyCode = "USD"): string {
  const spentMinorUnits = budgetMinorUnits(spent, currencyCode);
  const budgetMinorUnitsValue = budgetMinorUnits(budget, currencyCode);
  if (budgetMinorUnitsValue <= 0) return "No budget set";
  const status = categoryBudgetStatus(spent, budget, currencyCode);
  if (status === "over") {
    return `${formatMoney(amountFromMinorUnits(spentMinorUnits - budgetMinorUnitsValue, currencyCode), currencyCode)} over`;
  }
  if (status === "at-limit") return "At limit";
  return `${formatMoney(amountFromMinorUnits(budgetMinorUnitsValue - spentMinorUnits, currencyCode), currencyCode)} left`;
}

export function syncAgeLabel(lastSyncedAt: number, now = Date.now()): string {
  const seconds = Math.max(0, Math.floor((now - lastSyncedAt) / 1000));
  if (seconds < 10) return "just now";
  if (seconds < 60) return `${seconds}s ago`;
  const minutes = Math.floor(seconds / 60);
  if (minutes < 60) return `${minutes}m ago`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `${hours}h ago`;
  return `${Math.floor(hours / 24)}d ago`;
}

export function draftHasChanges<T>(initial: T, current: T): boolean {
  return JSON.stringify(initial) !== JSON.stringify(current);
}
