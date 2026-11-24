<script setup>
import { ref, computed } from 'vue'
import { useCartStore } from '../stores/cart'
import SearchBox from './SearchBox.vue'
import ProductItem from './ProductItem.vue'

const props = defineProps({
  products: { type: Array, required: true }
})

const cart = useCartStore()

const query = ref('')
const category = ref('')

const categories = computed(() => [...new Set(props.products.map((product) => product.category))])

const filteredProducts = computed(() => {
  const term = query.value.trim().toLowerCase()
  return props.products.filter(
    (product) =>
      (!category.value || product.category === category.value) &&
      (!term || product.name.toLowerCase().includes(term))
  )
})
</script>

<template>
  <section>
    <SearchBox @search="query = $event" />
    <select v-model="category">
      <option value="">All categories</option>
      <option v-for="option in categories" :key="option" :value="option">{{ option }}</option>
    </select>
    <ul v-if="filteredProducts.length">
      <ProductItem
        v-for="product in filteredProducts"
        :key="product.id"
        :product="product"
        @add="cart.add"
      />
    </ul>
    <p v-else>No products</p>
  </section>
</template>
