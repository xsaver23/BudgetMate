import { describe, expect, it, beforeEach } from "vitest";
import { defaultBudgetSettings } from "../domain/defaults";
import type { AppState } from "../domain/types";
import { fetchCloudPages, selectCloudBudgetId } from "./cloudRepository";
import { cloudSelectedBudgetStorageKey, cloudStateStorageKey, loadCloudState, saveState } from "./storage";

class MemoryStorage implements Storage {
  private readonly values = new Map<string, string>();

  get length() { return this.values.size; }
  clear() { this.values.clear(); }
  getItem(key: string) { return this.values.get(key) ?? null; }
  key(index: number) { return [...this.values.keys()][index] ?? null; }
  removeItem(key: string) { this.values.delete(key); }
  setItem(key: string, value: string) { this.values.set(key, value); }
}

const storage = new MemoryStorage();

beforeEach(() => {
  storage.clear();
  Object.defineProperty(globalThis, "window", { configurable: true, value: { localStorage: storage } });
});

describe("cloud integrity", () => {
  it("reads every page when a cloud table crosses the 1000-row boundary", async () => {
    const rows = Array.from({ length: 1001 }, (_, index) => index);
    const cursors: Array<string | undefined> = [];

    const result = await fetchCloudPages((afterId) => {
      cursors.push(afterId);
      const start = afterId ? Number(afterId) + 1 : 0;
      const page = rows.slice(start, Math.min(start + 100, rows.length));
      return Promise.resolve({ data: page, count: rows.length - start, nextCursor: String(start + page.length - 1), error: null });
    });

    expect(result).toEqual(rows);
    expect(cursors).toEqual([undefined, "99", "199", "299", "399", "499", "599", "699", "799", "899", "999", "1000"]);
  });

  it("fails the whole read when a later page errors", async () => {
    const error = new Error("page unavailable");

    await expect(fetchCloudPages((afterId) => Promise.resolve({
      data: afterId ? null : Array.from({ length: 1000 }, (_, index) => index),
      count: 1001,
      nextCursor: "999",
      error: afterId ? error : null
    }))).rejects.toBe(error);
  });

  it("fails closed when a page count is smaller than the returned rows", async () => {
    await expect(fetchCloudPages((afterId) => Promise.resolve({
      data: Array.from({ length: 100 }, (_, index) => index),
      count: afterId ? 99 : 100,
      nextCursor: afterId ? "199" : "99",
      error: null
    }))).rejects.toThrow("could not be read completely");
  });

  it("fails closed when the server omits the total count", async () => {
    await expect(fetchCloudPages(() => Promise.resolve({
      data: [1],
      error: null
    }))).rejects.toThrow("could not be read completely");
  });

  it("keeps keyset paging stable across an equal-count insert and delete", async () => {
    let rows = Array.from({ length: 1002 }, (_, index) => index);
    let firstPage = true;
    const result = await fetchCloudPages((afterId) => {
      if (firstPage) {
        firstPage = false;
      } else if (rows.includes(50)) {
        rows = rows.filter((row) => row !== 50);
        rows.splice(rows.indexOf(1001), 0, 1000.5);
      }
      const start = afterId ? rows.findIndex((row) => row > Number(afterId)) : 0;
      const page = rows.slice(start < 0 ? rows.length : start, (start < 0 ? rows.length : start) + 100);
      return Promise.resolve({
        data: page,
        count: rows.length - (start < 0 ? rows.length : start),
        nextCursor: page.length > 0 ? String(page[page.length - 1]) : null,
        error: null
      });
    });

    // The already-consumed deleted row may remain in this non-atomic pass;
    // every untouched row and the tail insertion must still be present.
    expect(result).toEqual([
      ...Array.from({ length: 1001 }, (_, index) => index),
      1000.5,
      1001
    ]);
  });

  it("restores a selected household only from that user's cloud cache", () => {
    const userA = "user-a";
    const userB = "user-b";
    const sharedBudget = "shared-budget";
    const state: AppState = {
      budgets: [
        { id: userA, ownerUserId: userA, name: "My Budget", createdAt: "now", updatedAt: "now" },
        { id: sharedBudget, ownerUserId: userA, name: "Household", createdAt: "now", updatedAt: "now" }
      ],
      currentBudgetId: sharedBudget,
      currentUserId: userA,
      members: [],
      transactions: [],
      settlements: [],
      settingsByBudgetId: { [userA]: defaultBudgetSettings(userA), [sharedBudget]: defaultBudgetSettings(sharedBudget) }
    };

    saveState(state, cloudStateStorageKey(userA));

    expect(loadCloudState(userA).currentBudgetId).toBe(sharedBudget);
    saveState({ ...state, currentBudgetId: userA }, cloudStateStorageKey(userA));
    expect(loadCloudState(userA).currentBudgetId).toBe(userA);
    expect(loadCloudState(userB).currentUserId).toBe(userB);
    expect(loadCloudState(userB).currentBudgetId).toBe(userB);
  });

  it("uses the sole shared household for a fresh account without a saved choice", () => {
    const userId = "user-a";
    const sharedBudget = "shared-budget";

    expect(selectCloudBudgetId(userId, [userId, sharedBudget], userId)).toBe(sharedBudget);
    expect(selectCloudBudgetId(userId, [userId, sharedBudget], userId, "other-user-budget")).toBe(sharedBudget);
    expect(selectCloudBudgetId(userId, [userId, sharedBudget], userId, userId)).toBe(userId);
  });

  it("migrates a legacy cached personal choice before cloud refresh", () => {
    const userId = "user-a";
    const sharedBudget = "shared-budget";
    const legacyState: AppState = {
      budgets: [
        { id: userId, ownerUserId: userId, name: "My Budget", createdAt: "now", updatedAt: "now" },
        { id: sharedBudget, ownerUserId: userId, name: "Household", createdAt: "now", updatedAt: "now" }
      ],
      currentBudgetId: userId,
      currentUserId: userId,
      members: [],
      transactions: [],
      settlements: [],
      settingsByBudgetId: { [userId]: defaultBudgetSettings(userId), [sharedBudget]: defaultBudgetSettings(sharedBudget) }
    };

    storage.setItem(cloudStateStorageKey(userId), JSON.stringify(legacyState));
    expect(storage.getItem(cloudSelectedBudgetStorageKey(userId))).toBeNull();

    expect(loadCloudState(userId).currentBudgetId).toBe(userId);
    expect(storage.getItem(cloudSelectedBudgetStorageKey(userId))).toBe(userId);
  });
});
