import { createSeedState } from "./seedData";
import type { AppState } from "../domain/types";

const storageKey = "budgetmate-web-state-v1";

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

export function loadState(): AppState {
  const rawState = window.localStorage.getItem(storageKey);
  if (!rawState) {
    return createSeedState();
  }

  try {
    const parsed = JSON.parse(rawState) as unknown;
    return isAppState(parsed) ? parsed : createSeedState();
  } catch {
    return createSeedState();
  }
}

export function saveState(state: AppState): void {
  window.localStorage.setItem(storageKey, JSON.stringify(state));
}

export function resetState(): AppState {
  const nextState = createSeedState();
  saveState(nextState);
  return nextState;
}

export function exportState(state: AppState): string {
  return JSON.stringify(state, null, 2);
}

export function importState(rawState: string): AppState | null {
  try {
    const parsed = JSON.parse(rawState) as unknown;
    if (!isAppState(parsed)) {
      return null;
    }
    saveState(parsed);
    return parsed;
  } catch {
    return null;
  }
}
