import { createContext } from 'svelte';

export const [getCurrency, setCurrency] = createContext();

export function formatMoney(amount, currency) {
  return new Intl.NumberFormat('en-US', { style: 'currency', currency }).format(amount);
}
