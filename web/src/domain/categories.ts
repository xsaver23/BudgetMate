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
  rent: "#173404",
  bills: "#FFCF70",
  studentLoans: "#7B6EE6",
  subscription: "#1FA37D",
  food: "#9CC957",
  groceries: "#9CC957",
  health: "#3B8FE2",
  household: "#F5E6C9",
  gas: "#FFCA6A",
  parking: "#8B4E0A",
  transportation: "#1FA37D",
  shopping: "#F49379",
  restaurant: "#E2572E",
  date: "#F49379",
  vacation: "#7B6EE6",
  entertainment: "#3B8FE2",
  gift: "#FFCF70",
  refund: "#1FA37D",
  work: "#9CC957",
  eTransfer: "#1FA37D",
  other: "#FFCF70"
};

const darkCategoryColors = new Set(["#173404", "#8B4E0A", "#1FA37D", "#E2572E", "#7B6EE6", "#3B8FE2"]);

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
  return darkCategoryColors.has(categoryColor(id)) ? "#FFFDF7" : "#173404";
}
