import { describe, expect, it } from "vitest";
import {
  gateCEnabledKey,
  gateCReadOnlyMessage,
  gateCRolloutState,
  gateCServerReadyKey,
  moneyServerBridgeEnabledKey
} from "./gateCRollout";
import { GateCFinancialWritesDisabledError, retryGateCMutation, upsertCloudTransaction } from "./cloudRepository";

describe("Gate C web rollout", () => {
  it("fails closed when markers are absent or only partly enabled", () => {
    expect(gateCRolloutState({})).toBe("disabled");
    expect(gateCRolloutState({ [gateCServerReadyKey]: "YES" })).toBe("inconsistent");
    expect(gateCRolloutState({
      [gateCServerReadyKey]: "YES",
      [gateCEnabledKey]: "NO",
      [moneyServerBridgeEnabledKey]: "YES"
    })).toBe("inconsistent");
  });

  it("only enables financial writes when every deliberate marker agrees", () => {
    expect(gateCRolloutState({
      [gateCServerReadyKey]: " yes ",
      [gateCEnabledKey]: "YES",
      [moneyServerBridgeEnabledKey]: "YES"
    })).toBe("enabled");
    expect(gateCRolloutState({
      [gateCServerReadyKey]: "YES",
      [gateCEnabledKey]: "maybe",
      [moneyServerBridgeEnabledKey]: "YES"
    })).toBe("inconsistent");
  });

  it("provides a user-visible deferred/read-only explanation", () => {
    expect(gateCReadOnlyMessage("disabled")).toMatch(/temporarily unavailable/i);
    expect(gateCReadOnlyMessage("inconsistent")).toMatch(/configuration is incomplete/i);
  });

  it("blocks a default-build financial write before it can reach Supabase", async () => {
    await expect(upsertCloudTransaction({
      id: "00000000-0000-0000-0000-000000000001",
      budgetId: "00000000-0000-0000-0000-000000000002",
      userId: "00000000-0000-0000-0000-000000000003",
      title: "Lunch",
      amount: 12,
      type: "expense",
      category: "food",
      createdByMemberId: "00000000-0000-0000-0000-000000000004",
      date: "2026-07-30T12:00:00Z",
      createdAt: "2026-07-30T12:00:00Z",
      splits: []
    }, "00000000-0000-0000-0000-000000000003")).rejects.toBeInstanceOf(GateCFinancialWritesDisabledError);
  });

  it("retries a transport failure once without changing the logical operation", async () => {
    let calls = 0;
    const result = await retryGateCMutation(async () => {
      calls += 1;
      if (calls === 1) throw { message: "Network request timed out" };
      return "replayed receipt";
    });

    expect(result).toBe("replayed receipt");
    expect(calls).toBe(2);
  });
});
