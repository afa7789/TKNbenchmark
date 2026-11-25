<script setup>
import { useCurrencyFormatter } from '../currency.js'

const { product } = defineProps({
  product: { type: Object, required: true },
})
const emit = defineEmits(['add'])
const format = useCurrencyFormatter()
</script>

<template>
  <li>
    {{ product.name }} — {{ format(product.price) }}
    <button type="button" @click="emit('add', product)">Add</button>
  </li>
</template>
