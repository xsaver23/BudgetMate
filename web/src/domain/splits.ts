import { amountMinorUnits } from "./currency";

export type SplitAllocation = {
  memberId: string;
  amountMinorUnits: number;
};

export type CustomSplitValidation = {
  status: "valid" | "under" | "over" | "invalid";
  totalMinorUnits?: number;
  differenceMinorUnits?: number;
};

export function allocateEqualSplitMinorUnits(
  totalMinorUnits: number,
  participantIds: string[],
  payerId?: string
): SplitAllocation[] | undefined {
  if (!Number.isSafeInteger(totalMinorUnits) || totalMinorUnits <= 0 || participantIds.length === 0) {
    return undefined;
  }
  if (new Set(participantIds).size !== participantIds.length || participantIds.some((id) => !id)) {
    return undefined;
  }

  const orderedIds = [...participantIds].sort((left, right) => left < right ? -1 : left > right ? 1 : 0);
  if (payerId && orderedIds.includes(payerId)) {
    orderedIds.splice(orderedIds.indexOf(payerId), 1);
    orderedIds.unshift(payerId);
  }
  const base = Math.floor(totalMinorUnits / orderedIds.length);
  const remainder = totalMinorUnits % orderedIds.length;
  const allocations = orderedIds.map((memberId, index) => ({
    memberId,
    amountMinorUnits: base + (index < remainder ? 1 : 0)
  }));
  return allocations.every((allocation) => allocation.amountMinorUnits > 0) ? allocations : undefined;
}

export function validateCustomSplitAmounts(
  totalMinorUnits: number | undefined,
  participantIds: string[],
  values: Record<string, string>,
  currencyCode: string
): CustomSplitValidation {
  if (
    totalMinorUnits === undefined ||
    !Number.isSafeInteger(totalMinorUnits) ||
    totalMinorUnits <= 0 ||
    participantIds.length === 0 ||
    new Set(participantIds).size !== participantIds.length
  ) {
    return { status: "invalid" };
  }

  const parsed = participantIds.map((memberId) => amountMinorUnits(values[memberId] ?? "", currencyCode));
  const parsedValues = parsed.filter((value): value is number => value !== undefined);
  if (parsedValues.length !== parsed.length || parsedValues.some((value) => value <= 0)) {
    return { status: "invalid" };
  }
  const splitTotal = parsedValues.reduce((sum, value) => sum + value, 0);
  if (!Number.isSafeInteger(splitTotal)) {
    return { status: "invalid" };
  }
  const differenceMinorUnits = totalMinorUnits - splitTotal;
  return {
    status: differenceMinorUnits === 0 ? "valid" : differenceMinorUnits > 0 ? "under" : "over",
    totalMinorUnits: splitTotal,
    differenceMinorUnits: Math.abs(differenceMinorUnits)
  };
}
