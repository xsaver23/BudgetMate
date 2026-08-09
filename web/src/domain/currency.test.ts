import { describe, expect, it } from "vitest";
import { amountMinorUnits, currencySymbol, formatMoney } from "./currency";

describe("currencySymbol", () => {
  it("matches the symbols used by the iOS app", () => {
    expect(currencySymbol("CAD")).toBe("$");
    expect(formatMoney(1234.5, "CAD")).toBe("$1,234.50");
    expect(currencySymbol("EUR")).toBe("€");
    expect(currencySymbol("GBP")).toBe("£");
    expect(currencySymbol("PHP")).toBe("₱");
    expect(currencySymbol("JPY")).toBe("¥");
  });
});

describe("amountMinorUnits", () => {
  it("rounds decimal text without binary floating-point drift", () => {
    expect(amountMinorUnits("1.005", "USD")).toBe(101);
    expect(amountMinorUnits("123.4", "CAD")).toBe(12340);
    expect(amountMinorUnits("1.5", "JPY")).toBe(2);
  });
});
