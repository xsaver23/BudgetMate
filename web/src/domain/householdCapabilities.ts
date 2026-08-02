import type { Budget, BudgetMember } from "./types";

export const householdOwnerOnlyMessage = "Only the household owner can change this.";

export type HouseholdIdentity = {
  id: string;
  email?: string | null;
};

export type HouseholdCapabilities = {
  currentMember?: BudgetMember;
  isActiveMember: boolean;
  isOwner: boolean;
  canEditCurrency: boolean;
  canManageMembers: boolean;
};

export type SyncMode = "cloud" | "local";

function normalizedEmail(email?: string | null): string {
  return email?.trim().toLowerCase() ?? "";
}

export function authenticatedBudgetMember(
  members: BudgetMember[],
  identity?: HouseholdIdentity
): BudgetMember | undefined {
  if (!identity) {
    return undefined;
  }

  const email = normalizedEmail(identity.email);
  return (
    members.find((member) => member.authUserId === identity.id || member.id === identity.id) ??
    (email ? members.find((member) => normalizedEmail(member.email) === email) : undefined)
  );
}

export function deriveHouseholdCapabilities(
  budget: Budget | undefined,
  members: BudgetMember[],
  identity?: HouseholdIdentity
): HouseholdCapabilities {
  const currentMember = budget
    ? authenticatedBudgetMember(
        members.filter((member) => member.budgetId === budget.id),
        identity
      )
    : undefined;
  const isActiveMember = currentMember?.inviteStatus === "active";
  const isOwner = Boolean(
    budget &&
      identity &&
      isActiveMember &&
      currentMember?.role === "owner" &&
      budget.ownerUserId === identity.id
  );

  return {
    currentMember,
    isActiveMember,
    isOwner,
    canEditCurrency: isOwner,
    canManageMembers: isOwner
  };
}

export function modeAfterSignOut(supabaseConfigured: boolean): SyncMode {
  return supabaseConfigured ? "cloud" : "local";
}

export function authEntryIsVisible(
  syncMode: SyncMode,
  hasSession: boolean,
  supabaseConfigured: boolean
): boolean {
  return supabaseConfigured && syncMode === "cloud" && !hasSession;
}
