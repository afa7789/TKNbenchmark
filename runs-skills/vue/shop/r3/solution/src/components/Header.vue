<script setup>
import { useCartStore } from '../stores/cart.js'

const emit = defineEmits(['checkout'])
const cart = useCartStore()
</script>

<template>
  <header>
    <span>Cart: {{ cart.count }} items</span>
    <button type="button" @click="emit('checkout')">Checkout</button>
  </header>
</template>
