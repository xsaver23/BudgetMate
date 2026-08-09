import type { BudgetMember } from "./types";

export type CurrencyFinancialHistoryState = "knownEmpty" | "populated";
export type CurrencyHistoryVerification = "verified" | "loading" | "unverified";

export const currencyCheckingHistoryMessage =
  "Checking this household’s financial history before currency can be changed.";
export const currencyFinancialHistoryMessage =
  "Currency can’t be changed after financial activity is added. Existing amounts are not converted, and currency conversion isn’t supported yet.";
export const currencyUnverifiedHistoryMessage =
  "Currency can’t be changed because this household’s financial history can’t be verified. Existing amounts are not converted, and currency conversion isn’t supported yet.";
export const sharedRecordMutationReadOnlyMessage =
  "Only the household owner or the authenticated record creator can edit or delete shared records right now.";

export function currencyFinancialHistoryState(input: {
  transactionCount: number;
  settlementCount: number;
  categoryBudgetKeys: string[];
}): CurrencyFinancialHistoryState {
  return input.transactionCount > 0 ||
    input.settlementCount > 0 ||
    input.categoryBudgetKeys.length > 0
    ? "populated"
    : "knownEmpty";
}

export function currencyChangeDecision(input: {
  activeBudgetId: string;
  presentedBudgetId: string;
  history: CurrencyFinancialHistoryState;
  verification: CurrencyHistoryVerification;
}): { isAllowed: boolean; reason: "available" | "checkingHistory" | "financialHistory" | "unverifiedHistory"; restrictionMessage?: string } {
  if (input.history === "populated") {
    return { isAllowed: false, reason: "financialHistory", restrictionMessage: currencyFinancialHistoryMessage };
  }
  if (input.verification === "unverified") {
    return { isAllowed: false, reason: "unverifiedHistory", restrictionMessage: currencyUnverifiedHistoryMessage };
  }
  if (
    input.verification === "loading" ||
    input.activeBudgetId !== input.presentedBudgetId
  ) {
    return { isAllowed: false, reason: "checkingHistory", restrictionMessage: currencyCheckingHistoryMessage };
  }
  return { isAllowed: true, reason: "available" };
}

export type RecordMutationOperation = "create" | "modifyExisting";
export type RecordMutationReason =
  | "personalBudget"
  | "householdOwner"
  | "householdCreator"
  | "activeHouseholdMemberCreating"
  | "restrictedSharedMember"
  | "sharedDataSafetyDisabled";

export function recordMutationDecision(input: {
  currentUserId: string;
  activeBudgetId: string;
  recordBudgetId: string;
  ownerUserId?: string;
  members: BudgetMember[];
  recordCreatorUserId?: string;
  legacyRecordCreatorUserId?: string;
  operation?: RecordMutationOperation;
  serverGateEnabled: boolean;
}): { isAllowed: boolean; reason: RecordMutationReason; readOnlyMessage?: string } {
  if (!input.serverGateEnabled) {
    return {
      isAllowed: false,
      reason: "sharedDataSafetyDisabled",
      readOnlyMessage: "Shared-data editing is temporarily unavailable."
    };
  }
  if (input.activeBudgetId !== input.recordBudgetId) {
    return { isAllowed: false, reason: "restrictedSharedMember", readOnlyMessage: sharedRecordMutationReadOnlyMessage };
  }
  if (input.recordBudgetId === input.currentUserId) {
    return { isAllowed: true, reason: "personalBudget" };
  }

  const authenticatedMembers = input.members.filter(
    (member) =>
      member.budgetId === input.activeBudgetId &&
      (member.authUserId === input.currentUserId ||
        (!member.authUserId && member.id === input.currentUserId))
  );
  const member = authenticatedMembers.length === 1 ? authenticatedMembers[0] : undefined;
  if (!member || member.inviteStatus !== "active") {
    return { isAllowed: false, reason: "restrictedSharedMember", readOnlyMessage: sharedRecordMutationReadOnlyMessage };
  }
  if (input.operation === "create") {
    return { isAllowed: true, reason: "activeHouseholdMemberCreating" };
  }
  if (member.role === "owner" && (!input.ownerUserId || input.ownerUserId === input.currentUserId)) {
    return { isAllowed: true, reason: "householdOwner" };
  }
  if (
    (input.recordCreatorUserId ?? input.legacyRecordCreatorUserId) === input.currentUserId
  ) {
    return { isAllowed: true, reason: "householdCreator" };
  }
  return { isAllowed: false, reason: "restrictedSharedMember", readOnlyMessage: sharedRecordMutationReadOnlyMessage };
}
