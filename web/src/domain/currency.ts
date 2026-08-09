export interface CurrencyOption {
  code: string;
  name: string;
  symbol: string;
}

export const currencyOptions: CurrencyOption[] = [
  { code: "USD", name: "US Dollar", symbol: "$" },
  { code: "CAD", name: "Canadian Dollar", symbol: "CA$" },
  { code: "EUR", name: "Euro", symbol: "€" },
  { code: "GBP", name: "British Pound", symbol: "£" },
  { code: "AUD", name: "Australian Dollar", symbol: "A$" },
  { code: "PHP", name: "Philippine Peso", symbol: "₱" },
  { code: "JPY", name: "Japanese Yen", symbol: "¥" }
];

export function normalizedCurrencyCode(code: string): string {
  const normalized = code.trim().toUpperCase();
  return currencyOptions.some((option) => option.code === normalized) ? normalized : "USD";
}

export function currencySymbol(code: string): string {
  const normalized = normalizedCurrencyCode(code);
  if (normalized === "CAD") {
    return "$";
  }
  return currencyOptions.find((option) => option.code === normalized)?.symbol ?? "$";
}

export function formatMoney(amount: number, currencyCode: string): string {
  const normalized = normalizedCurrencyCode(currencyCode);
  return new Intl.NumberFormat(normalized === "CAD" ? "en-CA" : "en-US", {
    style: "currency",
    currency: normalized,
    maximumFractionDigits: normalized === "JPY" ? 0 : 2
  }).format(amount);
}

export function formatAmountNumber(amount: number, currencyCode: string): string {
  return new Intl.NumberFormat("en-US", {
    style: "decimal",
    minimumFractionDigits: normalizedCurrencyCode(currencyCode) === "JPY" ? 0 : 2,
    maximumFractionDigits: normalizedCurrencyCode(currencyCode) === "JPY" ? 0 : 2
  }).format(amount);
}

export function amountMinorUnits(value: string | number, currencyCode: string): number | undefined {
  const fractionDigits = normalizedCurrencyCode(currencyCode) === "JPY" ? 0 : 2;
  const text = String(value).trim().replace(/^\+/, "");
  const match = /^(\d+)(?:\.(\d+))?$/.exec(text);
  if (!match) {
    return undefined;
  }

  const whole = match[1];
  const fraction = match[2] ?? "";
  const kept = fraction.slice(0, fractionDigits).padEnd(fractionDigits, "0");
  const shouldRound = fraction.length > fractionDigits && Number(fraction[fractionDigits]) >= 5;
  const scaled = Number(`${whole}${kept}` || "0") + (shouldRound ? 1 : 0);
  return Number.isSafeInteger(scaled) ? scaled : undefined;
}

export function amountFromMinorUnits(value: number, currencyCode: string): number {
  return value / (normalizedCurrencyCode(currencyCode) === "JPY" ? 1 : 100);
}
