import { describe, expect, it } from "vitest";
import { validateProfileName } from "./profile";

describe("profile name validation", () => {
  it("requires a trimmed name and rejects emoji like iOS", () => {
    expect(validateProfileName("  ")).toBe("Enter a profile name.");
    expect(validateProfileName("Avery Morgan")).toBeUndefined();
    expect(validateProfileName("Avery 123")).toBeUndefined();
    expect(validateProfileName("Avery 🐻")).toBe("Names cannot include emoji.");
    expect(validateProfileName("Avery 1️⃣")).toBe("Names cannot include emoji.");
    expect(validateProfileName("Avery ©️")).toBe("Names cannot include emoji.");
  });
});
