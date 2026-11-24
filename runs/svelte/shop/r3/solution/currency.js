import { getContext, setContext } from 'svelte';

const key = Symbol('currency');

export function setCurrency(currency) {
  setContext(key, currency);
}

export function getCurrency() {
  return getContext(key);
}

export function formatMoney(amount, currency) {
  return new Intl.NumberFormat(undefined, { style: 'currency', currency }).format(amount);
}
