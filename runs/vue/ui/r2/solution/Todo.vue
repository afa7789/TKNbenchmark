<script setup>
import { ref } from 'vue'

const text = ref('')
const items = ref([])
let nextId = 0

function add() {
  const value = text.value.trim()
  if (!value) return
  items.value.push({ id: nextId++, text: value })
  text.value = ''
}

function remove(id) {
  items.value = items.value.filter(item => item.id !== id)
}
</script>

<template>
  <div>
    <form @submit.prevent="add">
      <input v-model="text" />
      <button type="submit">Add</button>
    </form>
    <ul>
      <li v-for="item in items" :key="item.id">
        {{ item.text }}
        <button type="button" @click="remove(item.id)">Remove</button>
      </li>
    </ul>
  </div>
</template>
