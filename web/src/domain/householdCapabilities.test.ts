import { describe, expect, it } from "vitest";
import {
  authEntryIsVisible,
  deriveHouseholdCapabilities,
  modeAfterSignOut
} from "./householdCapabilities";
import type { Budget, BudgetMember } from "./types";

const budget: Budget = {
  id: "household-1",
  ownerUserId: "owner-1",
  name: "Home",
  createdAt: "2026-08-01T00:00:00.000Z",
  updatedAt: "2026-08-01T00:00:00.000Z"
};

const owner: BudgetMember = {
  id: "member-owner",
  budgetId: budget.id,
  displayName: "Owner One",
  email: "owner@example.com",
  initials: "OO",
  color: "#3B8FE2",
  authUserId: "owner-1",
  role: "owner",
  inviteStatus: "active",
  createdDate: "2026-08-01T00:00:00.000Z"
};

const member: BudgetMember = {
  id: "member-two",
  budgetId: budget.id,
  displayName: "Member Two",
  email: "member@example.com",
  initials: "MT",
  color: "#E2572E",
  authUserId: "member-2",
  role: "member",
  inviteStatus: "active",
  createdDate: "2026-08-01T00:00:00.000Z"
};

describe("household capabilities", () => {
  it("grants household controls only to the selected household owner", () => {
    const ownerCapabilities = deriveHouseholdCapabilities(budget, [owner, member], {
      id: "owner-1",
      email: "owner@example.com"
    });
    const memberCapabilities = deriveHouseholdCapabilities(budget, [owner, member], {
      id: "member-2",
      email: "member@example.com"
    });

    expect(ownerCapabilities.isOwner).toBe(true);
    expect(ownerCapabilities.canEditCurrency).toBe(true);
    expect(ownerCapabilities.canManageMembers).toBe(true);
    expect(memberCapabilities.isActiveMember).toBe(true);
    expect(memberCapabilities.isOwner).toBe(false);
    expect(memberCapabilities.canEditCurrency).toBe(false);
    expect(memberCapabilities.canManageMembers).toBe(false);
  });

  it("does not grant owner controls from a different household or a pending invite", () => {
    const pendingMember = { ...member, inviteStatus: "pending" as const };
    const otherHousehold = { ...budget, id: "household-2", ownerUserId: "owner-1" };

    expect(deriveHouseholdCapabilities(otherHousehold, [owner, member], { id: "owner-1" }).isOwner).toBe(false);
    expect(deriveHouseholdCapabilities(budget, [owner, pendingMember], { id: "member-2" }).isActiveMember).toBe(false);
  });
});

describe("auth surface transitions", () => {
  it("returns a signed-out cloud user to the auth entry instead of local data", () => {
    expect(modeAfterSignOut(true)).toBe("cloud");
    expect(authEntryIsVisible("cloud", false, true)).toBe(true);
    expect(authEntryIsVisible("local", false, true)).toBe(false);
  });

  it("keeps local mode behind an explicit local choice when cloud is unavailable", () => {
    expect(modeAfterSignOut(false)).toBe("local");
    expect(authEntryIsVisible("local", false, false)).toBe(false);
  });
});
