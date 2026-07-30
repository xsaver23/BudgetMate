export type GateCOperation = "insert" | "update" | "delete";
export type GateCRpcName = "mutate_budget_transaction" | "mutate_budget_settlement";

export type GateCMutationParameters = {
  p_budget_id: string;
  p_record_id: string;
  p_expected_row_version: number;
  p_client_mutation_id: string;
  p_operation: GateCOperation;
  p_payload: Record<string, unknown>;
};

export type QueuedGateCFinancialMutation = {
  userId: string;
  rpcName: GateCRpcName;
  parameters: GateCMutationParameters;
  queuedAt: string;
};

export type GateCMutationResult = {
  record_id: string;
  row_version: number;
  deleted: boolean;
  replayed: boolean;
};

export type GateCOutboxStorage = Pick<Storage, "getItem" | "setItem">;

export class GateCFinancialOutboxStorageError extends Error {
  constructor(message = "Financial changes could not be queued safely on this device.") {
    super(message);
    this.name = "GateCFinancialOutboxStorageError";
  }
}

function isMutation(value: unknown, userId: string): value is QueuedGateCFinancialMutation {
  if (!value || typeof value !== "object") return false;
  const candidate = value as Partial<QueuedGateCFinancialMutation>;
  const parameters = candidate.parameters as Partial<GateCMutationParameters> | undefined;
  return candidate.userId === userId &&
    (candidate.rpcName === "mutate_budget_transaction" || candidate.rpcName === "mutate_budget_settlement") &&
    typeof candidate.queuedAt === "string" &&
    !!parameters &&
    typeof parameters.p_budget_id === "string" &&
    typeof parameters.p_record_id === "string" &&
    typeof parameters.p_expected_row_version === "number" &&
    typeof parameters.p_client_mutation_id === "string" &&
    (parameters.p_operation === "insert" || parameters.p_operation === "update" || parameters.p_operation === "delete") &&
    !!parameters.p_payload && typeof parameters.p_payload === "object";
}

function defaultStorage(): GateCOutboxStorage {
  if (typeof window === "undefined" || !window.localStorage) {
    throw new GateCFinancialOutboxStorageError();
  }
  return window.localStorage;
}

/**
 * User-scoped, browser-local Gate C journal. It deliberately stores only the
 * idempotent RPC request, never authentication material. A completed request
 * is removed only after the server returns a normal or replayed receipt.
 */
export class GateCFinancialOutbox {
  private readonly inFlight = new Map<string, Promise<GateCMutationResult[]>>();

  constructor(private readonly configuredStorage?: GateCOutboxStorage) {}

  enqueue(mutation: QueuedGateCFinancialMutation): QueuedGateCFinancialMutation {
    const pending = this.load(mutation.userId);
    const existing = pending.find(
      (candidate) => candidate.parameters.p_client_mutation_id === mutation.parameters.p_client_mutation_id
    );
    if (existing) {
      if (
        existing.userId !== mutation.userId ||
        existing.rpcName !== mutation.rpcName ||
        JSON.stringify(existing.parameters) !== JSON.stringify(mutation.parameters)
      ) {
        throw new GateCFinancialOutboxStorageError("A pending financial change has a conflicting mutation id.");
      }
      return existing;
    }
    this.save(mutation.userId, [...pending, mutation]);
    return mutation;
  }

  pending(userId: string): QueuedGateCFinancialMutation[] {
    return this.load(userId);
  }

  async flush(
    userId: string,
    execute: (mutation: QueuedGateCFinancialMutation) => Promise<GateCMutationResult>
  ): Promise<GateCMutationResult[]> {
    const afterPrevious = this.inFlight.get(userId) ?? Promise.resolve([]);
    const run = afterPrevious.catch(() => []).then(async () => {
      const results: GateCMutationResult[] = [];
      while (true) {
        const next = this.load(userId)[0];
        if (!next) return results;
        const result = await execute(next);
        const remaining = this.load(userId).filter(
          (candidate) => candidate.parameters.p_client_mutation_id !== next.parameters.p_client_mutation_id
        );
        this.save(userId, remaining);
        results.push(result);
      }
    });
    this.inFlight.set(userId, run);
    try {
      return await run;
    } finally {
      if (this.inFlight.get(userId) === run) {
        this.inFlight.delete(userId);
      }
    }
  }

  private key(userId: string) {
    return `budgetmate.gate-c-financial-outbox.v1:${userId}`;
  }

  private load(userId: string): QueuedGateCFinancialMutation[] {
    let raw: string | null;
    try {
      raw = this.storage().getItem(this.key(userId));
    } catch {
      throw new GateCFinancialOutboxStorageError();
    }
    if (!raw) return [];
    try {
      const parsed: unknown = JSON.parse(raw);
      if (!Array.isArray(parsed) || !parsed.every((item) => isMutation(item, userId))) {
        throw new GateCFinancialOutboxStorageError("Queued financial changes on this device are invalid and were not sent.");
      }
      return parsed;
    } catch (error) {
      if (error instanceof GateCFinancialOutboxStorageError) throw error;
      throw new GateCFinancialOutboxStorageError("Queued financial changes on this device are invalid and were not sent.");
    }
  }

  private save(userId: string, mutations: QueuedGateCFinancialMutation[]) {
    try {
      this.storage().setItem(this.key(userId), JSON.stringify(mutations));
    } catch {
      throw new GateCFinancialOutboxStorageError();
    }
  }

  private storage(): GateCOutboxStorage {
    return this.configuredStorage ?? defaultStorage();
  }
}
