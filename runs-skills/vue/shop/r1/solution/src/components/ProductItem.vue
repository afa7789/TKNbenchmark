<script setup>
import { inject } from 'vue'

const { product } = defineProps({
  product: { type: Object, required: true },
})
const emit = defineEmits(['add'])

const currency = inject('currency')
const format = (value) => new Intl.NumberFormat('en-US', { style: 'currency', currency }).format(value)
</script>

<template>
  <li>
    <span>{{ product.name }}</span>
    <span>{{ format(product.price) }}</span>
    <button type="button" @click="emit('add', product)">Add</button>
  </li>
</template>
