import { createSeedState } from "./seedData";
import { defaultBudgetSettings } from "../domain/defaults";
import { uniqueTransactions } from "../domain/budgetMath";
import type { AppState } from "../domain/types";

const baseStorageKey = "budgetmate-web-state-v1";
export const localStateStorageKey = `${baseStorageKey}:local`;

export function cloudStateStorageKey(userId: string): string {
  return `${baseStorageKey}:cloud:${userId}`;
}

export function loadCloudState(userId: string): AppState {
  const cached = loadState(cloudStateStorageKey(userId));
  if (cached.currentUserId === userId) {
    return cached;
  }

  const now = new Date().toISOString();
  return {
    budgets: [{ id: userId, ownerUserId: userId, name: "My Budget", createdAt: now, updatedAt: now }],
    currentBudgetId: userId,
    currentUserId: userId,
    members: [],
    transactions: [],
    settlements: [],
    settingsByBudgetId: { [userId]: defaultBudgetSettings(userId) }
  };
}

function isAppState(value: unknown): value is AppState {
  if (!value || typeof value !== "object") {
    return false;
  }

  const candidate = value as Partial<AppState>;
  return (
    Array.isArray(candidate.budgets) &&
    typeof candidate.currentBudgetId === "string" &&
    typeof candidate.currentUserId === "string" &&
    Array.isArray(candidate.members) &&
    Array.isArray(candidate.transactions) &&
    Array.isArray(candidate.settlements) &&
    !!candidate.settingsByBudgetId
  );
}

export function loadState(storageKey = localStateStorageKey): AppState {
  const rawState = window.localStorage.getItem(storageKey);
  if (!rawState) {
    return createSeedState();
  }

  try {
    const parsed = JSON.parse(rawState) as unknown;
    return isAppState(parsed) ? sanitizeState(parsed) : createSeedState();
  } catch {
    return createSeedState();
  }
}

export function saveState(state: AppState, storageKey = localStateStorageKey): void {
  window.localStorage.setItem(storageKey, JSON.stringify(sanitizeState(state)));
}

export function clearState(storageKey: string): void {
  window.localStorage.removeItem(storageKey);
}

export function resetState(storageKey = localStateStorageKey): AppState {
  const nextState = createSeedState();
  saveState(nextState, storageKey);
  return nextState;
}

export function exportState(state: AppState): string {
  return JSON.stringify(sanitizeState(state), null, 2);
}

export function importState(rawState: string): AppState | null {
  try {
    const parsed = JSON.parse(rawState) as unknown;
    if (!isAppState(parsed)) {
      return null;
    }
    return sanitizeState(parsed);
  } catch {
    return null;
  }
}

export function appStatesEqual(left: AppState, right: AppState): boolean {
  return JSON.stringify(sanitizeState(left)) === JSON.stringify(sanitizeState(right));
}

function sanitizeState(state: AppState): AppState {
  return {
    ...state,
    transactions: uniqueTransactions(state.transactions)
  };
}
