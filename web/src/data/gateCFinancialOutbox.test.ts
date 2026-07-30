import { describe, expect, it } from "vitest";
import {
  buildSettlementDeleteGateCMutation,
  buildSettlementGateCMutation,
  buildTransactionDeleteGateCMutation,
  buildTransactionGateCMutation
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
      p_payload: { title: "Lunch", created_by_member_id: memberId, amount: 12.5 }
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

  it("builds settlement RPC requests with the same CAS/delete contract", () => {
    const settlement = {
      id: recordId,
      budgetId,
      userId: userA,
      fromMemberId: memberId,
      toMemberId: userB,
      amount: 3.75,
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
        p_payload: { from_member_id: memberId, to_member_id: userB, amount: 3.75 }
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
