<script setup>
import { computed, inject } from 'vue'
import { useCart } from './useCart.js'

const { state, remove, setQuantity } = useCart()
const currency = inject('currency')

const formatter = computed(() => new Intl.NumberFormat(undefined, { style: 'currency', currency }))
const subtotal = computed(() => state.items.reduce((sum, item) => sum + item.price * item.quantity, 0))
const tax = computed(() => subtotal.value * 0.1)
const total = computed(() => subtotal.value + tax.value)
</script>

<template>
  <section>
    <h2>Cart</h2>
    <ul>
      <li v-for="item in state.items" :key="item.id">
        <span>{{ item.name }}</span>
        <input
          v-model.number="item.quantity"
          type="number"
          min="1"
          @change="setQuantity(item.id, item.quantity)"
        />
        <span>{{ formatter.format(item.price * item.quantity) }}</span>
        <button type="button" @click="remove(item.id)">Remove</button>
      </li>
    </ul>
    <p>Subtotal: {{ formatter.format(subtotal) }}</p>
    <p>Tax: {{ formatter.format(tax) }}</p>
    <p>Total: {{ formatter.format(total) }}</p>
  </section>
</template>
