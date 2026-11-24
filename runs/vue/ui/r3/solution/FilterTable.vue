<script setup>
import { ref, computed } from 'vue'

const props = defineProps({
  rows: { type: Array, default: () => [] }
})

const columns = ['name', 'price', 'qty']
const query = ref('')
const sortKey = ref(null)
const sortAsc = ref(true)

function sortBy(key) {
  if (sortKey.value === key) {
    sortAsc.value = !sortAsc.value
  } else {
    sortKey.value = key
    sortAsc.value = true
  }
}

const visibleRows = computed(() => {
  const q = query.value.toLowerCase()
  const filtered = props.rows.filter((row) => row.name.toLowerCase().includes(q))
  if (!sortKey.value) return filtered
  const key = sortKey.value
  const dir = sortAsc.value ? 1 : -1
  return [...filtered].sort((a, b) => {
    const x = a[key]
    const y = b[key]
    if (typeof x === 'string') return x.localeCompare(y) * dir
    return (x - y) * dir
  })
})

const total = computed(() =>
  visibleRows.value.reduce((sum, row) => sum + row.price * row.qty, 0)
)
</script>

<template>
  <div>
    <input v-model="query" type="search" placeholder="Search" />
    <table>
      <thead>
        <tr>
          <th v-for="col in columns" :key="col" @click="sortBy(col)">
            {{ col }}
            <span v-if="sortKey === col">{{ sortAsc ? '▲' : '▼' }}</span>
          </th>
        </tr>
      </thead>
      <tbody>
        <tr v-for="(row, i) in visibleRows" :key="row.name + i">
          <td>{{ row.name }}</td>
          <td>{{ row.price }}</td>
          <td>{{ row.qty }}</td>
        </tr>
      </tbody>
      <tfoot>
        <tr>
          <td colspan="2">Total</td>
          <td>{{ total }}</td>
        </tr>
      </tfoot>
    </table>
  </div>
</template>
