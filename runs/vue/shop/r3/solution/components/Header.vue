<script setup>
import { storeToRefs } from 'pinia'
import { useCartStore } from '../stores/cart'

const emit = defineEmits(['checkout'])

const { count } = storeToRefs(useCartStore())
</script>

<template>
  <header>
    <span>Cart: {{ count }} items</span>
    <button type="button" @click="emit('checkout')">Checkout</button>
  </header>
</template>
