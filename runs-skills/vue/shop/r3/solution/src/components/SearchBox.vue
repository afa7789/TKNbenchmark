<script setup>
import { ref, watch, onUnmounted } from 'vue'

const emit = defineEmits(['search'])
const query = ref('')
let timer = null

watch(query, (value) => {
  clearTimeout(timer)
  timer = setTimeout(() => emit('search', value), 300)
})

onUnmounted(() => clearTimeout(timer))
</script>

<template>
  <input v-model="query" type="search" placeholder="Search products" />
</template>
