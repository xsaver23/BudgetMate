import type { AppState, BudgetSettings } from "../domain/types";

const currentUserId = "00000000-0000-4000-8000-000000000001";
const budgetId = "00000000-0000-4000-8000-000000000101";
const today = new Date();
const iso = (dayOffset = 0) => {
  const date = new Date(today);
  date.setDate(today.getDate() + dayOffset);
  return date.toISOString();
};

const settings: BudgetSettings = {
  budgetId,
  currencyCode: "USD",
  appearance: "system",
  categoryBudgets: {
    rent: 2200,
    groceries: 650,
    bills: 430,
    transportation: 260,
    restaurant: 260,
    entertainment: 180,
    household: 220,
    other: 300
  },
  categoryEmojis: {}
};

export function createSeedState(): AppState {
  const members = [
    {
      id: "00000000-0000-4000-8000-000000000201",
      budgetId,
      displayName: "Avery Morgan",
      email: "avery@example.com",
      initials: "AM",
      color: "#3B8FE2",
      authUserId: currentUserId,
      role: "owner" as const,
      inviteStatus: "active" as const,
      joinedDate: iso(-45),
      createdDate: iso(-45)
    },
    {
      id: "00000000-0000-4000-8000-000000000202",
      budgetId,
      displayName: "Jordan Lee",
      email: "jordan@example.com",
      initials: "JL",
      color: "#E2572E",
      role: "member" as const,
      inviteStatus: "active" as const,
      joinedDate: iso(-42),
      createdDate: iso(-42)
    },
    {
      id: "00000000-0000-4000-8000-000000000203",
      budgetId,
      displayName: "Mina Patel",
      email: "mina@example.com",
      initials: "MP",
      color: "#1FA37D",
      role: "member" as const,
      inviteStatus: "active" as const,
      joinedDate: iso(-20),
      createdDate: iso(-20)
    }
  ];

  return {
    budgets: [
      {
        id: budgetId,
        ownerUserId: currentUserId,
        name: "Home Budget",
        createdAt: iso(-45),
        updatedAt: iso(-2)
      }
    ],
    currentBudgetId: budgetId,
    currentUserId,
    members,
    transactions: [
      {
        id: "00000000-0000-4000-8000-000000000301",
        budgetId,
        userId: currentUserId,
        title: "Paycheck",
        amount: 4200,
        type: "income",
        category: "work",
        paymentMethod: "card",
        createdByMemberId: members[0].id,
        date: iso(-13),
        createdAt: iso(-13),
        splits: []
      },
      {
        id: "00000000-0000-4000-8000-000000000302",
        budgetId,
        userId: currentUserId,
        title: "Rent",
        amount: 2200,
        type: "expense",
        category: "rent",
        paymentMethod: "card",
        createdByMemberId: members[0].id,
        date: iso(-11),
        createdAt: iso(-11),
        splits: [
          { id: "00000000-0000-4000-8000-000000000401", memberId: members[0].id, amount: 1100 },
          { id: "00000000-0000-4000-8000-000000000402", memberId: members[1].id, amount: 1100 }
        ]
      },
      {
        id: "00000000-0000-4000-8000-000000000303",
        budgetId,
        userId: currentUserId,
        title: "Groceries",
        amount: 184.72,
        type: "expense",
        category: "groceries",
        paymentMethod: "card",
        createdByMemberId: members[1].id,
        date: iso(-7),
        createdAt: iso(-7),
        splits: [
          { id: "00000000-0000-4000-8000-000000000403", memberId: members[0].id, amount: 61.57 },
          { id: "00000000-0000-4000-8000-000000000404", memberId: members[1].id, amount: 61.57 },
          { id: "00000000-0000-4000-8000-000000000405", memberId: members[2].id, amount: 61.58 }
        ]
      },
      {
        id: "00000000-0000-4000-8000-000000000304",
        budgetId,
        userId: currentUserId,
        title: "Internet",
        amount: 89,
        type: "expense",
        category: "bills",
        paymentMethod: "card",
        createdByMemberId: members[2].id,
        date: iso(-5),
        createdAt: iso(-5),
        splits: [
          { id: "00000000-0000-4000-8000-000000000406", memberId: members[0].id, amount: 29.67 },
          { id: "00000000-0000-4000-8000-000000000407", memberId: members[1].id, amount: 29.67 },
          { id: "00000000-0000-4000-8000-000000000408", memberId: members[2].id, amount: 29.66 }
        ]
      },
      {
        id: "00000000-0000-4000-8000-000000000305",
        budgetId,
        userId: currentUserId,
        title: "Dinner out",
        amount: 96.4,
        type: "expense",
        category: "restaurant",
        paymentMethod: "card",
        createdByMemberId: members[0].id,
        date: iso(-2),
        createdAt: iso(-2),
        splits: []
      }
    ],
    settlements: [
      {
        id: "00000000-0000-4000-8000-000000000501",
        budgetId,
        userId: currentUserId,
        fromMemberId: members[1].id,
        toMemberId: members[0].id,
        amount: 300,
        date: iso(-3)
      }
    ],
    settingsByBudgetId: {
      [budgetId]: settings
    }
  };
}
