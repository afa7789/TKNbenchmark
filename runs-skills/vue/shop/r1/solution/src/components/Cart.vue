<script setup>
import { computed, inject } from 'vue'
import { storeToRefs } from 'pinia'
import { useCartStore } from '../stores/cart'

const cart = useCartStore()
const { items, subtotal } = storeToRefs(cart)

const tax = computed(() => subtotal.value * 0.1)
const total = computed(() => subtotal.value + tax.value)

const currency = inject('currency')
const formatter = computed(() => new Intl.NumberFormat('en-US', { style: 'currency', currency }))
const format = (value) => formatter.value.format(value)
</script>

<template>
  <section>
    <h2>Cart</h2>
    <ul>
      <li v-for="item in items" :key="item.id">
        <span>{{ item.name }}</span>
        <input
          v-model.number="item.quantity"
          type="number"
          min="1"
          @change="cart.setQuantity(item.id, item.quantity)"
        />
        <button type="button" @click="cart.remove(item.id)">Remove</button>
      </li>
    </ul>
    <p>Subtotal: {{ format(subtotal) }}</p>
    <p>Tax: {{ format(tax) }}</p>
    <p>Total: {{ format(total) }}</p>
  </section>
</template>
