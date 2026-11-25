<script setup>
import { ref, provide } from 'vue'
import Header from './components/Header.vue'
import ProductList from './components/ProductList.vue'
import Cart from './components/Cart.vue'
import Modal from './components/Modal.vue'
import CheckoutForm from './components/CheckoutForm.vue'

const { products } = defineProps({
  products: { type: Array, required: true },
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
