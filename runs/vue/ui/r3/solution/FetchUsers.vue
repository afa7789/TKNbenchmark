<script setup>
import { ref, onMounted, onBeforeUnmount } from 'vue'

const users = ref([])
const loading = ref(true)
const error = ref(null)
const controller = new AbortController()

onMounted(async () => {
  try {
    const res = await fetch('https://jsonplaceholder.typicode.com/users', {
      signal: controller.signal
    })
    if (!res.ok) throw new Error(`HTTP ${res.status}`)
    users.value = await res.json()
  } catch (e) {
    if (e.name !== 'AbortError') error.value = e
  } finally {
    loading.value = false
  }
})

onBeforeUnmount(() => controller.abort())
</script>

<template>
  <p v-if="loading">Loading…</p>
  <p v-else-if="error">Error: {{ error.message }}</p>
  <ul v-else>
    <li v-for="user in users" :key="user.id">{{ user.name }}</li>
  </ul>
</template>
