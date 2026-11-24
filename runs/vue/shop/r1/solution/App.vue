<script setup>
import { ref, provide } from 'vue'
import Header from './Header.vue'
import ProductList from './ProductList.vue'
import Cart from './Cart.vue'
import Modal from './Modal.vue'
import CheckoutForm from './CheckoutForm.vue'

defineProps({
  products: { type: Array, required: true }
})

provide('currency', 'USD')

const checkoutOpen = ref(false)
</script>

<template>
  <Header @checkout="checkoutOpen = true" />
  <ProductList :products="products" />
  <Cart />
  <Modal v-if="checkoutOpen" @close="checkoutOpen = false">
    <CheckoutForm @submitted="checkoutOpen = false" />
  </Modal>
</template>
