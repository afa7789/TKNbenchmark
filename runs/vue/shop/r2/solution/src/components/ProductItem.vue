<script setup>
import { inject, computed } from 'vue'

const props = defineProps({
  product: { type: Object, required: true }
})

const emit = defineEmits(['add'])

const currency = inject('currency')

const formattedPrice = computed(() =>
  new Intl.NumberFormat(undefined, { style: 'currency', currency }).format(props.product.price)
)
</script>

<template>
  <li>
    <span>{{ product.name }}</span>
    <span>{{ formattedPrice }}</span>
    <button type="button" @click="emit('add', product)">Add</button>
  </li>
</template>
