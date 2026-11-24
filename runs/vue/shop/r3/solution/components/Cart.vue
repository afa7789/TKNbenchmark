<script setup>
import { inject, computed } from 'vue'
import { useCartStore } from '../stores/cart'

const TAX_RATE = 0.1

const cart = useCartStore()
const currency = inject('currency')

const formatter = computed(() => new Intl.NumberFormat(undefined, { style: 'currency', currency }))

const subtotal = computed(() => cart.items.reduce((sum, item) => sum + item.price * item.quantity, 0))
const tax = computed(() => subtotal.value * TAX_RATE)
const total = computed(() => subtotal.value + tax.value)

function format(amount) {
  return formatter.value.format(amount)
}
</script>

<template>
  <section>
    <h2>Cart</h2>
    <ul>
      <li v-for="item in cart.items" :key="item.id">
        <span>{{ item.name }}</span>
        <input v-model.number="item.quantity" type="number" min="1" />
        <button type="button" @click="cart.remove(item.id)">Remove</button>
      </li>
    </ul>
    <p>Subtotal: {{ format(subtotal) }}</p>
    <p>Tax: {{ format(tax) }}</p>
    <p>Total: {{ format(total) }}</p>
  </section>
</template>
