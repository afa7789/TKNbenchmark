import { reactive, computed } from 'vue'

const state = reactive({ items: [] })

const count = computed(() => state.items.reduce((sum, item) => sum + item.quantity, 0))

function add(product) {
  const existing = state.items.find((item) => item.id === product.id)
  if (existing) existing.quantity++
  else state.items.push({ ...product, quantity: 1 })
}

function remove(id) {
  state.items = state.items.filter((item) => item.id !== id)
}

function setQuantity(id, quantity) {
  const n = Math.floor(Number(quantity))
  if (!Number.isFinite(n) || n <= 0) return remove(id)
  const item = state.items.find((item) => item.id === id)
  if (item) item.quantity = n
}

function clear() {
  state.items = []
}

export function useCart() {
  return { state, count, add, remove, setQuantity, clear }
}
