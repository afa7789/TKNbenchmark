<script setup>
import { ref, onUnmounted } from 'vue'

const emit = defineEmits(['search'])
const query = ref('')
let timer = null

function onInput() {
  clearTimeout(timer)
  timer = setTimeout(() => {
    timer = null
    emit('search', query.value)
  }, 300)
}

onUnmounted(() => clearTimeout(timer))
</script>

<template>
  <input v-model="query" type="search" placeholder="Search" @input="onInput" />
</template>
