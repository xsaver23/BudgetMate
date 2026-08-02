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
