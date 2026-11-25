<script setup>
import { ref, onMounted } from 'vue'

const { baseUrl } = defineProps({ baseUrl: { type: String, required: true } })

const keys = ref([])
const selected = ref(null)
const selectedValue = ref('')
const newKey = ref('')
const newValue = ref('')
const error = ref(null)

const url = (key) => `${baseUrl.replace(/\/$/, '')}/kv${key == null ? '' : `/${encodeURIComponent(key)}`}`

async function request(key, options) {
  const res = await fetch(url(key), options)
  if (!res.ok) throw new Error(`${res.status} ${res.statusText}`)
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

async function loadKeys() {
  keys.value = await (await request()).json()
}

const reload = () => run(loadKeys)

const show = (key) =>
  run(async () => {
    selectedValue.value = await (await request(key)).text()
    selected.value = key
  })

const save = () =>
  run(async () => {
    if (!newKey.value) return
    await request(newKey.value, { method: 'PUT', body: newValue.value })
    if (selected.value === newKey.value) selectedValue.value = newValue.value
    newKey.value = ''
    newValue.value = ''
    await loadKeys()
  })

const remove = (key) =>
  run(async () => {
    await request(key, { method: 'DELETE' })
    if (selected.value === key) selected.value = null
    await loadKeys()
  })

onMounted(reload)
</script>

<template>
  <p v-if="error" role="alert">Error: {{ error }}</p>
  <form @submit.prevent="save">
    <input v-model="newKey" placeholder="Key" required />
    <input v-model="newValue" placeholder="Value" />
    <button type="submit">Save</button>
  </form>
  <ul>
    <li v-for="key in keys" :key="key">
      <button type="button" @click="show(key)">{{ key }}</button>
      <button type="button" @click="remove(key)">Delete</button>
    </li>
  </ul>
  <section v-if="selected !== null">
    <h3>{{ selected }}</h3>
    <pre>{{ selectedValue }}</pre>
  </section>
</template>
