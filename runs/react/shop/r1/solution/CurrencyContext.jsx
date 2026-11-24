import { createContext, useContext } from "react";

export const CurrencyContext = createContext("USD");

export function useCurrency() {
  return useContext(CurrencyContext);
}

export function formatMoney(amount, currency) {
  return new Intl.NumberFormat(undefined, { style: "currency", currency }).format(amount);
}
