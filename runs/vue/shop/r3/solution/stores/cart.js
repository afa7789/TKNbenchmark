import { defineStore } from 'pinia'
import { ref, computed } from 'vue'

export const useCartStore = defineStore('cart', () => {
  const items = ref([])

  const count = computed(() => items.value.reduce((sum, item) => sum + item.quantity, 0))

  function add(product) {
    const existing = items.value.find((item) => item.id === product.id)
    if (existing) {
      existing.quantity++
    } else {
      items.value.push({ ...product, quantity: 1 })
    }
  }

  function remove(id) {
    items.value = items.value.filter((item) => item.id !== id)
  }

  function setQuantity(id, quantity) {
    const item = items.value.find((item) => item.id === id)
    if (!item) return
    if (quantity > 0) {
      item.quantity = quantity
    } else {
      remove(id)
    }
  }

  function clear() {
    items.value = []
  }

  return { items, count, add, remove, setQuantity, clear }
})
