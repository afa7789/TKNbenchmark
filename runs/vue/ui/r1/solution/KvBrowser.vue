<script setup>
import { ref, onMounted } from 'vue'

const props = defineProps({ baseUrl: { type: String, required: true } })

const keys = ref([])
const selected = ref(null)
const value = ref('')
const newKey = ref('')
const newValue = ref('')
const error = ref(null)

async function request(path, options) {
  const res = await fetch(`${props.baseUrl}/kv${path}`, options)
  if (!res.ok) throw new Error(`HTTP ${res.status}`)
  return res
}

async function run(fn) {
  error.value = null
  try {
    await fn()
  } catch (e) {
    error.value = e.message
  }
}

async function fetchKeys() {
  keys.value = await (await request('')).json()
}

const loadKeys = () => run(fetchKeys)

const showKey = (key) =>
  run(async () => {
    value.value = await (await request(`/${encodeURIComponent(key)}`)).text()
    selected.value = key
  })

const save = () =>
  run(async () => {
    if (!newKey.value) return
    await request(`/${encodeURIComponent(newKey.value)}`, { method: 'PUT', body: newValue.value })
    if (selected.value === newKey.value) value.value = newValue.value
    newKey.value = ''
    newValue.value = ''
    await fetchKeys()
  })

const remove = (key) =>
  run(async () => {
    await request(`/${encodeURIComponent(key)}`, { method: 'DELETE' })
    if (selected.value === key) {
      selected.value = null
      value.value = ''
    }
    await fetchKeys()
  })

onMounted(loadKeys)
</script>

<template>
  <div>
    <p v-if="error">Error: {{ error }}</p>
    <form @submit.prevent="save">
      <input v-model="newKey" placeholder="Key" />
      <input v-model="newValue" placeholder="Value" />
      <button type="submit">Save</button>
    </form>
    <ul>
      <li v-for="key in keys" :key="key">
        <button type="button" @click="showKey(key)">{{ key }}</button>
        <button type="button" @click="remove(key)">Delete</button>
      </li>
    </ul>
    <div v-if="selected !== null">
      <h3>{{ selected }}</h3>
      <pre>{{ value }}</pre>
    </div>
  </div>
</template>
