<script setup>
import { ref, onMounted } from 'vue'

const { baseUrl } = defineProps({ baseUrl: { type: String, required: true } })

const keys = ref([])
const selectedKey = ref(null)
const selectedValue = ref('')
const newKey = ref('')
const newValue = ref('')
const error = ref(null)

async function request(path, options) {
  const res = await fetch(`${baseUrl.replace(/\/$/, '')}${path}`, options)
  if (!res.ok) throw new Error(`HTTP ${res.status} ${res.statusText}`.trim())
  return res
}

const keyPath = (key) => `/kv/${encodeURIComponent(key)}`

async function run(action) {
  error.value = null
  try {
    await action()
  } catch (e) {
    error.value = e.message
  }
}

async function fetchKeys() {
  keys.value = await (await request('/kv')).json()
}

const loadKeys = () => run(fetchKeys)

const mutate = (action) =>
  run(async () => {
    try {
      await action()
    } finally {
      await fetchKeys()
    }
  })

const showKey = (key) =>
  run(async () => {
    const value = await (await request(keyPath(key))).text()
    selectedKey.value = key
    selectedValue.value = value
  })

function save() {
  const key = newKey.value.trim()
  if (!key) return
  const value = newValue.value
  return mutate(async () => {
    await request(keyPath(key), { method: 'PUT', body: value })
    if (selectedKey.value === key) selectedValue.value = value
    newKey.value = ''
    newValue.value = ''
  })
}

const remove = (key) =>
  mutate(async () => {
    await request(keyPath(key), { method: 'DELETE' })
    if (selectedKey.value === key) selectedKey.value = null
  })

onMounted(loadKeys)
</script>

<template>
  <div>
    <p v-if="error" role="alert">Error: {{ error }}</p>
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
    <div v-if="selectedKey !== null">
      <h3>{{ selectedKey }}</h3>
      <pre>{{ selectedValue }}</pre>
    </div>
  </div>
</template>
