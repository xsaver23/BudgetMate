export interface CurrencyOption {
  code: string;
  name: string;
  symbol: string;
}

export const currencyOptions: CurrencyOption[] = [
  { code: "USD", name: "US Dollar", symbol: "$" },
  { code: "CAD", name: "Canadian Dollar", symbol: "CA$" },
  { code: "EUR", name: "Euro", symbol: "EUR" },
  { code: "GBP", name: "British Pound", symbol: "GBP" },
  { code: "AUD", name: "Australian Dollar", symbol: "A$" },
  { code: "PHP", name: "Philippine Peso", symbol: "PHP" },
  { code: "JPY", name: "Japanese Yen", symbol: "JPY" }
];

export function normalizedCurrencyCode(code: string): string {
  const normalized = code.trim().toUpperCase();
  return currencyOptions.some((option) => option.code === normalized) ? normalized : "USD";
}

export function formatMoney(amount: number, currencyCode: string): string {
  return new Intl.NumberFormat("en-US", {
    style: "currency",
    currency: normalizedCurrencyCode(currencyCode),
    maximumFractionDigits: normalizedCurrencyCode(currencyCode) === "JPY" ? 0 : 2
  }).format(amount);
}
