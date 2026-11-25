<script setup>
import { computed } from 'vue'
import { useCartStore } from '../stores/cart.js'
import { useCurrencyFormatter } from '../currency.js'

const TAX_RATE = 0.1

const cart = useCartStore()
const format = useCurrencyFormatter()

const tax = computed(() => cart.subtotal * TAX_RATE)
const total = computed(() => cart.subtotal + tax.value)
</script>

<template>
  <section>
    <h2>Cart</h2>
    <ul v-if="cart.items.length">
      <li v-for="item in cart.items" :key="item.product.id">
        {{ item.product.name }}
        <input
          type="number"
          min="1"
          v-model.number="item.quantity"
        />
        <button type="button" @click="cart.remove(item.product.id)">Remove</button>
      </li>
    </ul>
    <p v-else>Cart is empty</p>
    <p>Subtotal: {{ format(cart.subtotal) }}</p>
    <p>Tax: {{ format(tax) }}</p>
    <p>Total: {{ format(total) }}</p>
  </section>
</template>
