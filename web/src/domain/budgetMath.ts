import type {
  BudgetMember,
  BudgetSettings,
  BudgetTransaction,
  CategoryBreakdown,
  DashboardTotals,
  Settlement,
  SettlementSuggestion
} from "./types";

function cents(amount: number): number {
  return Math.round(amount * 100);
}

function monthKey(value: string | Date): string {
  const date = typeof value === "string" ? new Date(value) : value;
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}`;
}

const monthBudgetPrefix = "__monthBudget__:";

export function monthBudgetKey(selectedMonth: string, category: string): string {
  return `${monthBudgetPrefix}${selectedMonth}:${category}`;
}

export function isMonthBudgetKey(key: string): boolean {
  return key.startsWith(monthBudgetPrefix);
}

export function isInternalBudgetKey(key: string): boolean {
  return isMonthBudgetKey(key) || key.startsWith("__hiddenCategory__");
}

function monthAndCategory(key: string): { month: string; category: string } | undefined {
  if (!isMonthBudgetKey(key)) {
    return undefined;
  }
  const value = key.slice(monthBudgetPrefix.length);
  const separatorIndex = value.indexOf(":");
  if (separatorIndex < 0) {
    return undefined;
  }
  const month = value.slice(0, separatorIndex);
  const category = value.slice(separatorIndex + 1);
  return month && category ? { month, category } : undefined;
}

export function selectedCategoryBudgets(settings: BudgetSettings, selectedMonth: string): Record<string, number> {
  const legacy = Object.fromEntries(
    Object.entries(settings.categoryBudgets).filter(([key]) => !isMonthBudgetKey(key))
  );
  const scopedEntries = Object.entries(settings.categoryBudgets)
    .map(([key, value]) => ({ scoped: monthAndCategory(key), value }))
    .filter((entry): entry is { scoped: { month: string; category: string }; value: number } => !!entry.scoped);
  const prior = scopedEntries
    .filter((entry) => entry.scoped.month < selectedMonth)
    .sort((left, right) => left.scoped.month.localeCompare(right.scoped.month))
    .reduce<Record<string, number>>((result, entry) => {
      result[entry.scoped.category] = Math.max(0, entry.value);
      return result;
    }, { ...legacy });
  const exact = Object.fromEntries(
    scopedEntries
      .filter((entry) => entry.scoped.month === selectedMonth)
      .map((entry) => [entry.scoped.category, Math.max(0, entry.value)])
  );

  return { ...prior, ...exact };
}

function timestamp(value: string | Date | undefined): number {
  if (!value) {
    return 0;
  }
  const date = typeof value === "string" ? new Date(value) : value;
  const time = date.getTime();
  return Number.isNaN(time) ? 0 : time;
}

export function newestTransactionFirst(left: BudgetTransaction, right: BudgetTransaction): number {
  const dateDelta = timestamp(right.date) - timestamp(left.date);
  if (dateDelta !== 0) {
    return dateDelta;
  }

  const createdDelta = timestamp(right.createdAt) - timestamp(left.createdAt);
  if (createdDelta !== 0) {
    return createdDelta;
  }

  return left.title.localeCompare(right.title, undefined, { sensitivity: "base" });
}

export function uniqueTransactions(transactions: BudgetTransaction[]): BudgetTransaction[] {
  const transactionsById = new Map<string, BudgetTransaction>();

  for (const transaction of transactions) {
    const existing = transactionsById.get(transaction.id);
    if (!existing || newestTransactionFirst(transaction, existing) < 0) {
      transactionsById.set(transaction.id, transaction);
    }
  }

  return Array.from(transactionsById.values()).sort(newestTransactionFirst);
}

export function currentMonthKey(): string {
  return monthKey(new Date());
}

export function transactionsForMonth(transactions: BudgetTransaction[], selectedMonth: string) {
  return uniqueTransactions(transactions)
    .filter((transaction) => monthKey(transaction.date) === selectedMonth)
    .sort(newestTransactionFirst);
}

export function monthlyBudget(settings: BudgetSettings, selectedMonth?: string): number {
  const categoryBudgets = selectedMonth ? selectedCategoryBudgets(settings, selectedMonth) : settings.categoryBudgets;
  return Object.entries(categoryBudgets).reduce((total, [category, value]) => {
    if (isInternalBudgetKey(category)) {
      return total;
    }
    return total + Math.max(0, value);
  }, 0);
}

export function consumedExpense(transaction: BudgetTransaction, memberId: string): number {
  if (transaction.type !== "expense") {
    return 0;
  }

  if (transaction.splits.length > 0) {
    return transaction.splits.find((split) => split.memberId === memberId)?.amount ?? 0;
  }

  return transaction.createdByMemberId === memberId ? transaction.amount : 0;
}

export function involvesMember(transaction: BudgetTransaction, memberId: string): boolean {
  if (transaction.type === "expense") {
    if (transaction.splits.length > 0) {
      return transaction.splits.some((split) => split.memberId === memberId);
    }
    return transaction.createdByMemberId === memberId;
  }

  return transaction.createdByMemberId === memberId;
}

export function dashboardTotals(
  transactions: BudgetTransaction[],
  budgetLimit: number,
  memberId?: string
): DashboardTotals {
  const totalIncome = transactions
    .filter((transaction) => transaction.type === "income")
    .reduce((total, transaction) => {
      if (memberId) {
        return total + (transaction.createdByMemberId === memberId ? transaction.amount : 0);
      }
      return total + transaction.amount;
    }, 0);

  const totalExpenses = transactions
    .filter((transaction) => transaction.type === "expense")
    .reduce((total, transaction) => {
      if (memberId) {
        return total + consumedExpense(transaction, memberId);
      }
      return total + transaction.amount;
    }, 0);

  return {
    currentBalance: totalIncome - totalExpenses,
    totalIncome,
    totalExpenses,
    remainingBudget: budgetLimit - totalExpenses
  };
}

export function categoryBreakdown(transactions: BudgetTransaction[], memberId?: string): CategoryBreakdown[] {
  const totals = new Map<string, number>();

  for (const transaction of transactions) {
    if (transaction.type !== "expense") {
      continue;
    }

    const amount = memberId ? consumedExpense(transaction, memberId) : transaction.amount;
    if (amount <= 0) {
      continue;
    }
    totals.set(transaction.category, (totals.get(transaction.category) ?? 0) + amount);
  }

  return [...totals.entries()]
    .map(([category, amount]) => ({ category, amount }))
    .sort((left, right) => right.amount - left.amount);
}

export function memberExpenseTotals(transactions: BudgetTransaction[], members: BudgetMember[]) {
  return members.map((member) => ({
    member,
    amount: transactions
      .filter((transaction) => transaction.type === "expense")
      .reduce((total, transaction) => total + consumedExpense(transaction, member.id), 0)
  }));
}

export function settlementSuggestions(
  transactions: BudgetTransaction[],
  settlements: Settlement[],
  members: BudgetMember[]
): SettlementSuggestion[] {
  if (members.length < 2) {
    return [];
  }

  const membersById = new Map(members.map((member) => [member.id, member]));
  const directionalCents = new Map<string, number>();
  const directionalKey = (from: string, to: string) => `${from}::${to}`;

  for (const transaction of transactions) {
    if (transaction.type !== "expense" || transaction.splits.length === 0) {
      continue;
    }

    for (const split of transaction.splits) {
      if (split.memberId === transaction.createdByMemberId) {
        continue;
      }
      const amount = cents(split.amount);
      if (amount <= 0) {
        continue;
      }
      const key = directionalKey(split.memberId, transaction.createdByMemberId);
      directionalCents.set(key, (directionalCents.get(key) ?? 0) + amount);
    }
  }

  for (const settlement of settlements) {
    const amount = cents(settlement.amount);
    if (amount <= 0) {
      continue;
    }
    const key = directionalKey(settlement.fromMemberId, settlement.toMemberId);
    directionalCents.set(key, (directionalCents.get(key) ?? 0) - amount);
  }

  const processed = new Set<string>();
  const suggestions: SettlementSuggestion[] = [];

  for (const [key, amount] of directionalCents.entries()) {
    const [from, to] = key.split("::");
    const pairKey = [from, to].sort().join("::");
    if (processed.has(pairKey)) {
      continue;
    }
    processed.add(pairKey);

    const reverseAmount = directionalCents.get(directionalKey(to, from)) ?? 0;
    const netAmount = amount - reverseAmount;
    if (netAmount === 0) {
      continue;
    }

    const fromId = netAmount > 0 ? from : to;
    const toId = netAmount > 0 ? to : from;
    const debtor = membersById.get(fromId);
    const creditor = membersById.get(toId);
    if (!debtor || !creditor) {
      continue;
    }

    suggestions.push({
      id: `${fromId}-${toId}`,
      from: debtor,
      to: creditor,
      amount: Math.abs(netAmount) / 100
    });
  }

  return suggestions.sort((left, right) => {
    if (left.amount === right.amount) {
      return left.from.displayName.localeCompare(right.from.displayName);
    }
    return right.amount - left.amount;
  });
}

export function normalizeAmount(amount: number): number {
  if (!Number.isFinite(amount)) {
    return 0;
  }
  return Math.max(0, Math.round(amount * 100) / 100);
}
