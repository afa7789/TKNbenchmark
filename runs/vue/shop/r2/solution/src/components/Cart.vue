<script setup>
import { inject, computed } from 'vue'
import { useCartStore } from '../stores/cart'

const TAX_RATE = 0.1

const cart = useCartStore()
const currency = inject('currency')

const formatter = new Intl.NumberFormat(undefined, { style: 'currency', currency })
const format = (value) => formatter.format(value)

const tax = computed(() => cart.subtotal * TAX_RATE)
const total = computed(() => cart.subtotal + tax.value)
</script>

<template>
  <section>
    <h2>Cart</h2>
    <p v-if="!cart.items.length">Your cart is empty</p>
    <ul v-else>
      <li v-for="item in cart.items" :key="item.id">
        <span>{{ item.name }}</span>
        <input
          v-model.number="item.quantity"
          type="number"
          min="1"
          @change="cart.setQuantity(item.id, item.quantity)"
        />
        <span>{{ format(item.price * item.quantity) }}</span>
        <button type="button" @click="cart.remove(item.id)">Remove</button>
      </li>
    </ul>
    <dl>
      <dt>Subtotal</dt>
      <dd>{{ format(cart.subtotal) }}</dd>
      <dt>Tax (10%)</dt>
      <dd>{{ format(tax) }}</dd>
      <dt>Total</dt>
      <dd>{{ format(total) }}</dd>
    </dl>
  </section>
</template>
