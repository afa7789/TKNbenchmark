<script setup>
import { ref, computed } from 'vue'

const props = defineProps({
  rows: { type: Array, default: () => [] }
})

const columns = ['name', 'price', 'qty']
const query = ref('')
const sortKey = ref(null)
const sortAsc = ref(true)

const visibleRows = computed(() => {
  const q = query.value.toLowerCase()
  const filtered = props.rows.filter(row => row.name.toLowerCase().includes(q))
  if (!sortKey.value) return filtered
  const key = sortKey.value
  const dir = sortAsc.value ? 1 : -1
  return [...filtered].sort((a, b) => {
    const x = a[key]
    const y = b[key]
    const cmp = typeof x === 'string' ? x.localeCompare(y) : x - y
    return cmp * dir
  })
})

const total = computed(() =>
  visibleRows.value.reduce((sum, row) => sum + row.price * row.qty, 0)
)

function sortBy(key) {
  if (sortKey.value === key) {
    sortAsc.value = !sortAsc.value
  } else {
    sortKey.value = key
    sortAsc.value = true
  }
}
</script>

<template>
  <div>
    <input v-model="query" type="search" placeholder="Search" />
    <table>
      <thead>
        <tr>
          <th v-for="col in columns" :key="col" @click="sortBy(col)">
            {{ col }}{{ sortKey === col ? (sortAsc ? ' ▲' : ' ▼') : '' }}
          </th>
        </tr>
      </thead>
      <tbody>
        <tr v-for="(row, i) in visibleRows" :key="`${row.name}-${i}`">
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
