import { describe, expect, it } from "vitest";
import {
  buildSettlementDeleteGateCMutation,
  buildSettlementGateCMutation,
  buildTransactionDeleteGateCMutation,
  buildTransactionGateCMutation,
  mapTransaction,
  memberIdentityScopesByBudget,
  remapTransactionMembers
} from "./cloudRepository";
import {
  GateCFinancialOutbox,
  type GateCOutboxStorage,
  type QueuedGateCFinancialMutation
} from "./gateCFinancialOutbox";

const userA = "00000000-0000-0000-0000-000000000001";
const userB = "00000000-0000-0000-0000-000000000002";
const budgetId = "00000000-0000-0000-0000-000000000003";
const recordId = "00000000-0000-0000-0000-000000000004";
const memberId = "00000000-0000-0000-0000-000000000005";

class MemoryStorage implements GateCOutboxStorage {
  private readonly values = new Map<string, string>();

  getItem(key: string) {
    return this.values.get(key) ?? null;
  }

  setItem(key: string, value: string) {
    this.values.set(key, value);
  }
}

function transaction(rowVersion?: number) {
  return {
    id: recordId,
    budgetId,
    userId: userA,
    title: "Lunch",
    amount: 12.5,
    amountMinorUnits: 1250,
    currencyCode: "USD",
    type: "expense" as const,
    category: "food",
    createdByMemberId: memberId,
    date: "2026-07-30T12:00:00Z",
    createdAt: "2026-07-30T12:00:00Z",
    splits: [],
    rowVersion
  };
}

function receipt(mutation: QueuedGateCFinancialMutation) {
  return {
    record_id: mutation.parameters.p_record_id,
    row_version: mutation.parameters.p_expected_row_version + 1,
    deleted: mutation.parameters.p_operation === "delete",
    replayed: false
  };
}

describe("Gate C durable financial outbox", () => {
  it("builds the exact transaction RPC, operation, CAS value, UUID, and payload", () => {
    const insert = buildTransactionGateCMutation(transaction(), userA, "00000000-0000-0000-0000-000000000006");
    const update = buildTransactionGateCMutation(transaction(7), userA, "00000000-0000-0000-0000-000000000007");
    const deletion = buildTransactionDeleteGateCMutation(transaction(8), userA, "00000000-0000-0000-0000-000000000008");

    expect(insert.rpcName).toBe("mutate_budget_transaction");
    expect(insert.parameters).toMatchObject({
      p_budget_id: budgetId,
      p_record_id: recordId,
      p_expected_row_version: 0,
      p_client_mutation_id: "00000000-0000-0000-0000-000000000006",
      p_operation: "insert",
      p_payload: {
        title: "Lunch",
        created_by_member_id: memberId,
        amount: 12.5,
        amount_minor_units: 1250,
        currency_code: "USD"
      }
    });
    expect(update.parameters).toMatchObject({ p_expected_row_version: 7, p_operation: "update" });
    expect(deletion.parameters).toEqual({
      p_budget_id: budgetId,
      p_record_id: recordId,
      p_expected_row_version: 8,
      p_client_mutation_id: "00000000-0000-0000-0000-000000000008",
      p_operation: "delete",
      p_payload: {}
    });
  });

  it("dual-writes exact split units while preserving the legacy split payload", () => {
    const mutation = buildTransactionGateCMutation({
      ...transaction(),
      amount: 10.01,
      amountMinorUnits: 1001,
      splits: [
        { id: "00000000-0000-0000-0000-000000000013", memberId, amount: 3.34, amountMinorUnits: 334, currencyCode: "USD" },
        { id: "00000000-0000-0000-0000-000000000014", memberId: userB, amount: 6.67, amountMinorUnits: 667, currencyCode: "USD" }
      ]
    }, userA, "00000000-0000-0000-0000-000000000015");

    expect(mutation.parameters.p_payload).toMatchObject({
      splits: [
        { id: "00000000-0000-0000-0000-000000000013", member_id: memberId, amount: 3.34 },
        { id: "00000000-0000-0000-0000-000000000014", member_id: userB, amount: 6.67 }
      ],
      splits_minor_units: [
        { id: "00000000-0000-0000-0000-000000000013", member_id: memberId, amount_minor_units: 334, currency_code: "USD" },
        { id: "00000000-0000-0000-0000-000000000014", member_id: userB, amount_minor_units: 667, currency_code: "USD" }
      ]
    });
  });

  it("prefers exact transaction and split amounts when legacy values differ", () => {
    const mapped = mapTransaction({
      id: recordId,
      user_id: userA,
      budget_id: budgetId,
      title: "Lunch",
      amount: 99,
      amount_minor_units: 1001,
      currency_code: "USD",
      type: "expense",
      category: "food",
      payment_method: "card",
      created_by_member_id: memberId,
      date: "2026-07-30T12:00:00Z",
      created_at: "2026-07-30T12:00:00Z",
      recurrence_rule: null,
      splits: [{ id: recordId, member_id: memberId, amount: 88 }],
      splits_minor_units: [{ id: recordId, member_id: memberId, amount_minor_units: 1001, currency_code: "USD" }]
    });

    expect(mapped.amount).toBe(10.01);
    expect(mapped.splits[0].amount).toBe(10.01);
  });

  it("falls back to the row user member when a stale payer ID has no aliases", () => {
    const currentMemberId = "00000000-0000-0000-0000-000000000016";
    const mapped = remapTransactionMembers(
      {
        ...transaction(),
        userId: currentMemberId,
        createdByMemberId: "00000000-0000-0000-0000-000000000017"
      },
      new Map(),
      new Set([currentMemberId])
    );

    expect(mapped.createdByMemberId).toBe(currentMemberId);
  });

  it("resolves the same user to the member in the transaction budget", () => {
    const personalBudgetId = userA;
    const householdBudgetId = budgetId;
    const personalMemberId = "00000000-0000-0000-0000-000000000018";
    const householdMemberId = "00000000-0000-0000-0000-000000000019";
    const members = [
      {
        id: personalMemberId,
        budgetId: personalBudgetId,
        displayName: "Avery",
        initials: "AM",
        color: "#000000",
        authUserId: userA,
        role: "owner" as const,
        inviteStatus: "active" as const,
        createdDate: "2026-07-30T12:00:00Z"
      },
      {
        id: householdMemberId,
        budgetId: householdBudgetId,
        displayName: "Avery",
        initials: "AM",
        color: "#000000",
        authUserId: userA,
        role: "member" as const,
        inviteStatus: "active" as const,
        createdDate: "2026-07-30T12:00:00Z"
      }
    ];
    const householdScope = memberIdentityScopesByBudget(members, members, userA).get(householdBudgetId);
    const mapped = remapTransactionMembers(
      { ...transaction(), createdByMemberId: personalMemberId },
      householdScope?.aliases ?? new Map(),
      householdScope?.validMemberIds
    );

    expect(mapped.createdByMemberId).toBe(householdMemberId);
  });

  it("builds settlement RPC requests with the same CAS/delete contract", () => {
    const settlement = {
      id: recordId,
      budgetId,
      userId: userA,
      fromMemberId: memberId,
      toMemberId: userB,
      amount: 3.75,
      amountMinorUnits: 375,
      currencyCode: "CAD",
      date: "2026-07-30T12:00:00Z",
      rowVersion: 4
    };
    const update = buildSettlementGateCMutation(settlement, userA, "00000000-0000-0000-0000-000000000012");
    const deletion = buildSettlementDeleteGateCMutation(settlement, userA, "00000000-0000-0000-0000-000000000013");

    expect(update).toMatchObject({
      rpcName: "mutate_budget_settlement",
      parameters: {
        p_budget_id: budgetId,
        p_record_id: recordId,
        p_expected_row_version: 4,
        p_client_mutation_id: "00000000-0000-0000-0000-000000000012",
        p_operation: "update",
        p_payload: {
          from_member_id: memberId,
          to_member_id: userB,
          amount: 3.75,
          amount_minor_units: 375,
          currency_code: "CAD"
        }
      }
    });
    expect(deletion.parameters).toMatchObject({
      p_operation: "delete",
      p_expected_row_version: 4,
      p_payload: {}
    });
  });

  it("retains a failed request and rehydrates the identical RPC after reload", async () => {
    const storage = new MemoryStorage();
    const firstOutbox = new GateCFinancialOutbox(storage);
    const mutation = buildTransactionGateCMutation(transaction(), userA, "00000000-0000-0000-0000-000000000009");
    firstOutbox.enqueue(mutation);

    await expect(firstOutbox.flush(userA, async () => {
      throw new Error("offline");
    })).rejects.toThrow("offline");
    expect(firstOutbox.pending(userA)).toEqual([mutation]);

    const rehydratedOutbox = new GateCFinancialOutbox(storage);
    const delivered: QueuedGateCFinancialMutation[] = [];
    await rehydratedOutbox.flush(userA, async (request) => {
      delivered.push(request);
      return receipt(request);
    });

    expect(delivered).toEqual([mutation]);
    expect(delivered[0].parameters.p_client_mutation_id).toBe("00000000-0000-0000-0000-000000000009");
    expect(rehydratedOutbox.pending(userA)).toEqual([]);
  });

  it("removes only a confirmed success and never crosses user scopes", async () => {
    const outbox = new GateCFinancialOutbox(new MemoryStorage());
    const a = buildTransactionGateCMutation(transaction(), userA, "00000000-0000-0000-0000-000000000010");
    const b = buildTransactionGateCMutation({ ...transaction(), userId: userB }, userB, "00000000-0000-0000-0000-000000000011");
    outbox.enqueue(a);
    outbox.enqueue(b);

    const delivered: string[] = [];
    await outbox.flush(userA, async (request) => {
      delivered.push(request.userId);
      return receipt(request);
    });

    expect(delivered).toEqual([userA]);
    expect(outbox.pending(userA)).toEqual([]);
    expect(outbox.pending(userB)).toEqual([b]);
  });
});
