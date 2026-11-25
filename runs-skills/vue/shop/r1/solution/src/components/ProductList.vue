<script setup>
import { ref, computed } from 'vue'
import SearchBox from './SearchBox.vue'
import ProductItem from './ProductItem.vue'
import { useCartStore } from '../stores/cart'

const { products } = defineProps({
  products: { type: Array, required: true },
})

const cart = useCartStore()
const query = ref('')
const category = ref('')

const categories = computed(() => [...new Set(products.map((p) => p.category))])

const filtered = computed(() => {
  const q = query.value.trim().toLowerCase()
  return products.filter(
    (p) => (!category.value || p.category === category.value) && p.name.toLowerCase().includes(q),
  )
})
</script>

<template>
  <section>
    <SearchBox @search="query = $event" />
    <select v-model="category">
      <option value="">All categories</option>
      <option v-for="c in categories" :key="c" :value="c">{{ c }}</option>
    </select>
    <ul v-if="filtered.length">
      <ProductItem v-for="product in filtered" :key="product.id" :product="product" @add="cart.add" />
    </ul>
    <p v-else>No products</p>
  </section>
</template>
