<script setup>
import { ref, onMounted } from 'vue'

const props = defineProps({
  baseUrl: { type: String, required: true }
})

const keys = ref([])
const selected = ref(null)
const selectedValue = ref('')
const newKey = ref('')
const newValue = ref('')
const error = ref(null)

async function request(path, options) {
  const res = await fetch(`${props.baseUrl}${path}`, options)
  if (!res.ok) throw new Error(`HTTP ${res.status}`)
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

const loadKeys = () =>
  run(async () => {
    keys.value = await (await request('/kv')).json()
  })

const show = (key) =>
  run(async () => {
    selectedValue.value = await (await request(keyPath(key))).text()
    selected.value = key
  })

const save = () => {
  const key = newKey.value.trim()
  if (!key) return
  return run(async () => {
    await request(keyPath(key), { method: 'PUT', body: newValue.value })
    newKey.value = ''
    newValue.value = ''
    if (selected.value === key) selectedValue.value = await (await request(keyPath(key))).text()
    keys.value = await (await request('/kv')).json()
  })
}

const remove = (key) =>
  run(async () => {
    await request(keyPath(key), { method: 'DELETE' })
    if (selected.value === key) {
      selected.value = null
      selectedValue.value = ''
    }
    keys.value = await (await request('/kv')).json()
  })

onMounted(loadKeys)
</script>

<template>
  <div>
    <p v-if="error" role="alert">Error: {{ error }}</p>
    <ul>
      <li v-for="key in keys" :key="key">
        <button type="button" @click="show(key)">{{ key }}</button>
        <button type="button" @click="remove(key)">Delete</button>
      </li>
    </ul>
    <div v-if="selected !== null">
      <h3>{{ selected }}</h3>
      <pre>{{ selectedValue }}</pre>
    </div>
    <form @submit.prevent="save">
      <input v-model="newKey" placeholder="Key" />
      <input v-model="newValue" placeholder="Value" />
      <button type="submit">Save</button>
    </form>
  </div>
</template>
