<script setup>
import { computed, inject } from 'vue'
import { useCartStore } from '../stores/cart'

const cart = useCartStore()
const currency = inject('currency')

const tax = computed(() => cart.subtotal * 0.1)
const total = computed(() => cart.subtotal + tax.value)

const format = (value) => new Intl.NumberFormat(undefined, { style: 'currency', currency }).format(value)
</script>

<template>
  <section>
    <h2>Cart</h2>
    <ul>
      <li v-for="item in cart.items" :key="item.id">
        {{ item.name }}
        <input v-model.number="item.quantity" type="number" min="1" @change="cart.setQuantity(item.id, item.quantity)" />
        <button type="button" @click="cart.remove(item.id)">Remove</button>
      </li>
    </ul>
    <p>Subtotal: {{ format(cart.subtotal) }}</p>
    <p>Tax: {{ format(tax) }}</p>
    <p>Total: {{ format(total) }}</p>
  </section>
</template>
