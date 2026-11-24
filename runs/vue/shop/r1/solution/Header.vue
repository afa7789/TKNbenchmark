<script setup>
import { useCart } from './useCart.js'

const emit = defineEmits(['checkout'])
const { count } = useCart()
</script>

<template>
  <header>
    <span>Cart: {{ count }}</span>
    <button type="button" @click="emit('checkout')">Checkout</button>
  </header>
</template>
