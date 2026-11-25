import { inject } from 'vue'

export const currencyKey = Symbol('currency')

export function useCurrencyFormatter() {
  const currency = inject(currencyKey, 'USD')
  const formatter = new Intl.NumberFormat('en-US', { style: 'currency', currency })
  return (value) => formatter.format(value)
}
