import { describe, expect, it } from "vitest";
import { currencySymbol } from "./currency";

describe("currencySymbol", () => {
  it("matches the symbols used by the iOS app", () => {
    expect(currencySymbol("CAD")).toBe("CA$");
    expect(currencySymbol("EUR")).toBe("€");
    expect(currencySymbol("GBP")).toBe("£");
    expect(currencySymbol("PHP")).toBe("₱");
    expect(currencySymbol("JPY")).toBe("¥");
  });
});
