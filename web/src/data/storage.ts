import { createSeedState } from "./seedData";
import { defaultBudgetSettings } from "../domain/defaults";
import { uniqueTransactions } from "../domain/budgetMath";
import type { AppState } from "../domain/types";

const baseStorageKey = "budgetmate-web-state-v1";
export const localStateStorageKey = `${baseStorageKey}:local`;

export function cloudStateStorageKey(userId: string): string {
  return `${baseStorageKey}:cloud:${userId}`;
}

export function cloudSelectedBudgetStorageKey(userId: string): string {
  return `${baseStorageKey}:cloud-selected-budget:${userId}`;
}

function cloudUserIdForStorageKey(storageKey: string): string | undefined {
  const prefix = `${baseStorageKey}:cloud:`;
  if (!storageKey.startsWith(prefix)) return undefined;
  const userId = storageKey.slice(prefix.length);
  return userId && !userId.includes(":") ? userId : undefined;
}

export function loadCloudState(userId: string): AppState {
  const cached = loadState(cloudStateStorageKey(userId));
  if (cached.currentUserId === userId) {
    const selectionKey = cloudSelectedBudgetStorageKey(userId);
    const storedSelection = window.localStorage.getItem(selectionKey);
    // Migrate pre-selection caches without treating a brand-new account's
    // seed placeholder as a user choice.
    if (!storedSelection && cached.budgets.some((budget) => budget.id === cached.currentBudgetId)) {
      window.localStorage.setItem(selectionKey, cached.currentBudgetId);
    }
    const selectedBudgetId = storedSelection ?? cached.currentBudgetId;
    return selectedBudgetId && cached.budgets.some((budget) => budget.id === selectedBudgetId)
      ? { ...cached, currentBudgetId: selectedBudgetId }
      : cached;
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
  const sanitized = sanitizeState(state);
  window.localStorage.setItem(storageKey, JSON.stringify(sanitized));
  const userId = cloudUserIdForStorageKey(storageKey);
  if (userId && sanitized.currentUserId === userId && sanitized.budgets.some((budget) => budget.id === sanitized.currentBudgetId)) {
    const selectionKey = cloudSelectedBudgetStorageKey(userId);
    const priorSelection = window.localStorage.getItem(selectionKey);
    if (sanitized.currentBudgetId !== userId || priorSelection !== null) {
      window.localStorage.setItem(selectionKey, sanitized.currentBudgetId);
    }
  }
}

export function clearState(storageKey: string): void {
  window.localStorage.removeItem(storageKey);
  const userId = cloudUserIdForStorageKey(storageKey);
  if (userId) window.localStorage.removeItem(cloudSelectedBudgetStorageKey(userId));
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
