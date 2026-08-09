import { describe, expect, it } from "vitest";
import {
  currencyChangeDecision,
  currencyFinancialHistoryState,
  recordMutationDecision,
  sharedRecordMutationReadOnlyMessage
} from "./financialSafety";
import type { BudgetMember } from "./types";

const budgetId = "shared-budget";
const owner: BudgetMember = {
  id: "owner-member",
  budgetId,
  displayName: "Owner",
  initials: "O",
  color: "#000",
  authUserId: "owner-user",
  role: "owner",
  inviteStatus: "active",
  createdDate: "2026-08-01T00:00:00.000Z"
};
const member: BudgetMember = {
  ...owner,
  id: "member-id",
  displayName: "Member",
  initials: "M",
  authUserId: "member-user",
  role: "member"
};

describe("financial safety", () => {
  it("locks currency for every stored financial-history kind, including zero budget keys", () => {
    expect(currencyFinancialHistoryState({ transactionCount: 0, settlementCount: 0, categoryBudgetKeys: [] })).toBe("knownEmpty");
    for (const history of [
      { transactionCount: 1, settlementCount: 0, categoryBudgetKeys: [] },
      { transactionCount: 0, settlementCount: 1, categoryBudgetKeys: [] },
      { transactionCount: 0, settlementCount: 0, categoryBudgetKeys: ["internal:zero"] }
    ]) {
      expect(currencyFinancialHistoryState(history)).toBe("populated");
    }
  });

  it("only allows a verified empty active budget to change currency", () => {
    expect(currencyChangeDecision({
      activeBudgetId: budgetId,
      presentedBudgetId: budgetId,
      history: "knownEmpty",
      verification: "verified"
    }).isAllowed).toBe(true);
    expect(currencyChangeDecision({
      activeBudgetId: budgetId,
      presentedBudgetId: budgetId,
      history: "knownEmpty",
      verification: "loading"
    }).restrictionMessage).toContain("Checking");
    expect(currencyChangeDecision({
      activeBudgetId: budgetId,
      presentedBudgetId: budgetId,
      history: "knownEmpty",
      verification: "unverified"
    }).reason).toBe("unverifiedHistory");
    expect(currencyChangeDecision({
      activeBudgetId: budgetId,
      presentedBudgetId: budgetId,
      history: "populated",
      verification: "verified"
    }).reason).toBe("financialHistory");
  });

  it("allows personal records and shared creation, but only owner or creator edits shared records", () => {
    const base = {
      currentUserId: "member-user",
      activeBudgetId: budgetId,
      ownerUserId: "owner-user",
      members: [owner, member],
      serverGateEnabled: true
    };
    expect(recordMutationDecision({ ...base, activeBudgetId: "member-user", recordBudgetId: "member-user" }).isAllowed).toBe(true);
    expect(recordMutationDecision({ ...base, recordBudgetId: budgetId, operation: "create" }).isAllowed).toBe(true);
    expect(recordMutationDecision({
      ...base,
      recordBudgetId: budgetId,
      recordCreatorUserId: "member-user"
    }).reason).toBe("householdCreator");
    expect(recordMutationDecision({
      ...base,
      recordBudgetId: budgetId,
      legacyRecordCreatorUserId: "member-user"
    }).reason).toBe("householdCreator");
    expect(recordMutationDecision({ ...base, recordBudgetId: budgetId }).readOnlyMessage).toBe(sharedRecordMutationReadOnlyMessage);
    expect(recordMutationDecision({ ...base, recordBudgetId: budgetId, serverGateEnabled: false }).isAllowed).toBe(false);
  });
});
