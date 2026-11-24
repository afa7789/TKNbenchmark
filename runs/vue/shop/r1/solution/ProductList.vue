<script setup>
import { ref, computed } from 'vue'
import SearchBox from './SearchBox.vue'
import ProductItem from './ProductItem.vue'
import { useCart } from './useCart.js'

const props = defineProps({
  products: { type: Array, required: true }
})

const { add } = useCart()
const query = ref('')
const category = ref('')

const categories = computed(() => [...new Set(props.products.map((p) => p.category))])

const filtered = computed(() => {
  const q = query.value.trim().toLowerCase()
  return props.products.filter(
    (p) =>
      (!category.value || p.category === category.value) &&
      (!q || p.name.toLowerCase().includes(q))
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
      <ProductItem v-for="product in filtered" :key="product.id" :product="product" @add="add" />
    </ul>
    <p v-else>No products</p>
  </section>
</template>
