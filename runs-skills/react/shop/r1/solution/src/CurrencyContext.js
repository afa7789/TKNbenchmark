import { createContext, use } from 'react'

export const CurrencyContext = createContext('USD')

export function useCurrency() {
  return use(CurrencyContext)
}

export function formatMoney(amount, currency) {
  return new Intl.NumberFormat('en-US', { style: 'currency', currency }).format(amount)
}
