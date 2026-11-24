<script setup>
import { useCartStore } from '../stores/cart'

const emit = defineEmits(['open-checkout'])

const cart = useCartStore()
</script>

<template>
  <header>
    <span>Cart: {{ cart.count }} items</span>
    <button type="button" @click="emit('open-checkout')">Checkout</button>
  </header>
</template>
