import { describe, expect, it } from "vitest";
import { allocateEqualSplitMinorUnits, validateCustomSplitAmounts } from "./splits";

describe("exact split helpers", () => {
  it("starts equal-split remainder units with the payer, then stable IDs", () => {
    expect(allocateEqualSplitMinorUnits(1001, ["member-z", "payer", "member-a"], "payer")).toEqual([
      { memberId: "payer", amountMinorUnits: 334 },
      { memberId: "member-a", amountMinorUnits: 334 },
      { memberId: "member-z", amountMinorUnits: 333 }
    ]);
    expect(allocateEqualSplitMinorUnits(5, ["member-z", "member-a"], "payer")).toEqual([
      { memberId: "member-a", amountMinorUnits: 3 },
      { memberId: "member-z", amountMinorUnits: 2 }
    ]);
  });

  it("rejects an equal split when a selected member would receive zero units", () => {
    expect(allocateEqualSplitMinorUnits(1, ["payer", "member"], "payer")).toBeUndefined();
  });

  it("classifies custom totals from exact currency units", () => {
    expect(validateCustomSplitAmounts(1000, ["a", "b"], { a: "4.00", b: "6.00" }, "USD").status).toBe("valid");
    expect(validateCustomSplitAmounts(1000, ["a", "b"], { a: "4.00", b: "5.99" }, "USD")).toMatchObject({
      status: "under",
      differenceMinorUnits: 1
    });
    expect(validateCustomSplitAmounts(1000, ["a", "b"], { a: "4.00", b: "6.01" }, "USD")).toMatchObject({
      status: "over",
      differenceMinorUnits: 1
    });
    expect(validateCustomSplitAmounts(1000, ["a", "b"], { a: "nope", b: "6.00" }, "USD").status).toBe("invalid");
  });

  it("rejects a custom split with a selected zero-share member even when the total matches", () => {
    expect(validateCustomSplitAmounts(1000, ["a", "b"], { a: "0", b: "10.00" }, "USD").status).toBe("invalid");
  });
});
