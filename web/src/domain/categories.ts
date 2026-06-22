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

const categoryColors: Record<string, string> = {
  rent: "#1E3A2B",
  bills: "#E7B84B",
  studentLoans: "#5E5D50",
  subscription: "#3F9E5E",
  food: "#3F9E5E",
  groceries: "#3F9E5E",
  health: "#3B82C4",
  household: "#9A9788",
  gas: "#E7B84B",
  parking: "#9A8128",
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

const darkCategoryColors = new Set(["#1E3A2B", "#3F9E5E", "#D6694C", "#3B82C4", "#5E5D50"]);

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
  return categoryColors[id] ?? "#FFCF70";
}

export function categoryTextColor(id: string): string {
  return darkCategoryColors.has(categoryColor(id)) ? "#FFFFFF" : "#1F2419";
}
