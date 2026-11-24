<script setup>
import { ref, computed } from 'vue'
import { useCartStore } from '../stores/cart'

const emit = defineEmits(['submitted'])

const cart = useCartStore()

const name = ref('')
const email = ref('')

const nameError = computed(() => (name.value.trim() ? '' : 'Name is required'))
const emailError = computed(() => (email.value.includes('@') ? '' : 'Email must contain @'))
const isValid = computed(() => !nameError.value && !emailError.value)

function submit() {
  if (!isValid.value) return
  cart.clear()
  emit('submitted')
}
</script>

<template>
  <form @submit.prevent="submit">
    <label>
      Name
      <input v-model="name" type="text" />
    </label>
    <p v-if="nameError">{{ nameError }}</p>
    <label>
      Email
      <input v-model="email" type="email" />
    </label>
    <p v-if="emailError">{{ emailError }}</p>
    <button type="submit" :disabled="!isValid">Place order</button>
  </form>
</template>
