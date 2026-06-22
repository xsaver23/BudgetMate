export type TransactionType = "income" | "expense";
export type PaymentMethod = "cash" | "card" | "paypal";
export type MemberRole = "owner" | "member";
export type InviteStatus = "active" | "invited" | "pending";
export type Appearance = "system" | "light" | "dark";

export interface Budget {
  id: string;
  ownerUserId: string;
  name: string;
  createdAt: string;
  updatedAt: string;
}

export interface BudgetMember {
  id: string;
  budgetId: string;
  displayName: string;
  email?: string;
  initials: string;
  color: string;
  authUserId?: string;
  role: MemberRole;
  inviteStatus: InviteStatus;
  joinedDate?: string;
  createdDate: string;
}

export interface TransactionSplit {
  id: string;
  memberId: string;
  amount: number;
}

export interface BudgetTransaction {
  id: string;
  budgetId: string;
  userId: string;
  title: string;
  amount: number;
  type: TransactionType;
  category: string;
  paymentMethod?: PaymentMethod;
  createdByMemberId: string;
  date: string;
  createdAt: string;
  recurrenceRule?: string;
  splits: TransactionSplit[];
}

export interface Settlement {
  id: string;
  budgetId: string;
  userId: string;
  fromMemberId: string;
  toMemberId: string;
  amount: number;
  date: string;
}

export interface BudgetSettings {
  budgetId: string;
  currencyCode: string;
  appearance: Appearance;
  categoryBudgets: Record<string, number>;
  categoryEmojis: Record<string, string>;
}

export interface AppState {
  budgets: Budget[];
  currentBudgetId: string;
  currentUserId: string;
  members: BudgetMember[];
  transactions: BudgetTransaction[];
  settlements: Settlement[];
  settingsByBudgetId: Record<string, BudgetSettings>;
}

export interface BudgetInvite {
  id: string;
  budgetId: string;
  invitedByUserId: string;
  displayName: string;
  email: string;
  status: "pending" | "accepted" | "declined" | "cancelled";
  createdAt: string;
}

export interface DashboardTotals {
  currentBalance: number;
  totalIncome: number;
  totalExpenses: number;
  remainingBudget: number;
}

export interface SettlementSuggestion {
  id: string;
  from: BudgetMember;
  to: BudgetMember;
  amount: number;
}

export interface CategoryBreakdown {
  category: string;
  amount: number;
}
