/**
 * Gate C must be enabled deliberately in the build that follows a verified
 * server rollout. Missing, malformed, or partially enabled markers are all
 * fail-closed so an ordinary web build cannot issue incompatible financial
 * writes.
 */
export type GateCRolloutState = "disabled" | "enabled" | "inconsistent";

export const gateCServerReadyKey = "VITE_BUDGETMATE_GATE_C_SERVER_READY";
export const gateCEnabledKey = "VITE_BUDGETMATE_GATE_C_ENABLED";
export const moneyServerBridgeEnabledKey = "VITE_BUDGETMATE_MONEY_SERVER_BRIDGE_ENABLED";

function activationValue(rawValue?: string): "enabled" | "disabled" | "invalid" {
  switch (rawValue?.trim().toUpperCase()) {
    case "YES":
      return "enabled";
    case "":
    case "NO":
    case undefined:
      return "disabled";
    default:
      return "invalid";
  }
}

export function gateCRolloutState(values: Record<string, string | undefined>): GateCRolloutState {
  const markers = [gateCServerReadyKey, gateCEnabledKey, moneyServerBridgeEnabledKey].map((key) => activationValue(values[key]));
  if (markers.every((marker) => marker === "enabled")) return "enabled";
  if (markers.every((marker) => marker === "disabled")) return "disabled";
  return "inconsistent";
}

export function gateCReadOnlyMessage(state: GateCRolloutState): string {
  switch (state) {
    case "disabled":
      return "Cloud transaction and settle-up editing is temporarily unavailable while household safety is being enabled.";
    case "inconsistent":
      return "Cloud transaction and settle-up editing is unavailable because this build's Gate C rollout configuration is incomplete.";
    case "enabled":
      return "Cloud transaction and settle-up editing is temporarily unavailable.";
  }
}

const currentGateCState = gateCRolloutState(import.meta.env);

export const gateCFinancialWritesEnabled = currentGateCState === "enabled";
export const gateCFinancialWritesReadOnlyMessage = gateCReadOnlyMessage(currentGateCState);
