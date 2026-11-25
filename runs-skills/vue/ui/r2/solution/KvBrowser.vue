<script setup>
import { ref, onMounted } from 'vue'

const { baseUrl } = defineProps({ baseUrl: { type: String, required: true } })

const keys = ref([])
const selectedKey = ref(null)
const selectedValue = ref('')
const newKey = ref('')
const newValue = ref('')
const error = ref(null)

const url = (key) => `${baseUrl}/kv${key == null ? '' : `/${encodeURIComponent(key)}`}`

async function request(key, options) {
  const res = await fetch(url(key), options)
  if (!res.ok) throw new Error(`HTTP ${res.status} ${res.statusText}`)
  return res
}

async function run(action) {
  error.value = null
  try {
    await action()
  } catch (e) {
    error.value = e.message
  }
}

const loadKeys = () =>
  run(async () => {
    keys.value = await (await request()).json()
  })

const showKey = (key) =>
  run(async () => {
    selectedValue.value = await (await request(key)).text()
    selectedKey.value = key
  })

const save = () =>
  run(async () => {
    if (!newKey.value) return
    await request(newKey.value, { method: 'PUT', body: newValue.value })
    if (selectedKey.value === newKey.value) selectedValue.value = newValue.value
    newKey.value = ''
    newValue.value = ''
    await loadKeys()
  })

const remove = (key) =>
  run(async () => {
    await request(key, { method: 'DELETE' })
    if (selectedKey.value === key) selectedKey.value = null
    await loadKeys()
  })

onMounted(loadKeys)
</script>

<template>
  <div>
    <p v-if="error" role="alert">Error: {{ error }}</p>
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
    <form @submit.prevent="save">
      <input v-model="newKey" placeholder="Key" required />
      <input v-model="newValue" placeholder="Value" />
      <button type="submit">Save</button>
    </form>
  </div>
</template>
