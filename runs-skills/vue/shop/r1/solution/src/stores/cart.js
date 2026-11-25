import { ref, computed } from 'vue'
import { defineStore } from 'pinia'

export const useCartStore = defineStore('cart', () => {
  const items = ref([])

  const count = computed(() => items.value.reduce((sum, item) => sum + item.quantity, 0))
  const subtotal = computed(() => items.value.reduce((sum, item) => sum + item.price * item.quantity, 0))

  function add(product) {
    const existing = items.value.find((item) => item.id === product.id)
    if (existing) existing.quantity++
    else items.value.push({ id: product.id, name: product.name, price: product.price, quantity: 1 })
  }

  function remove(id) {
    items.value = items.value.filter((item) => item.id !== id)
  }

  function setQuantity(id, quantity) {
    const item = items.value.find((i) => i.id === id)
    if (!item) return
    const n = Math.floor(Number(quantity))
    if (!Number.isFinite(n) || n <= 0) remove(id)
    else item.quantity = n
  }

  function clear() {
    items.value = []
  }

  return { items, count, subtotal, add, remove, setQuantity, clear }
})
