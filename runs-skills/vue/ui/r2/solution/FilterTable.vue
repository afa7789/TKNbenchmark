<script setup>
import { ref, computed } from 'vue'

const { rows } = defineProps({ rows: { type: Array, default: () => [] } })

const columns = ['name', 'price', 'qty']
const query = ref('')
const sortKey = ref(null)
const sortDir = ref(1)

const visibleRows = computed(() => {
  const q = query.value.trim().toLowerCase()
  const filtered = rows.filter((row) => row.name.toLowerCase().includes(q))
  if (!sortKey.value) return filtered
  const key = sortKey.value
  return filtered.toSorted((a, b) => {
    const x = a[key]
    const y = b[key]
    const cmp = typeof x === 'string' ? x.localeCompare(y) : x - y
    return cmp * sortDir.value
  })
})

const total = computed(() =>
  visibleRows.value.reduce((sum, row) => sum + row.price * row.qty, 0),
)

function sortBy(key) {
  if (sortKey.value === key) {
    sortDir.value = -sortDir.value
  } else {
    sortKey.value = key
    sortDir.value = 1
  }
}
</script>

<template>
  <div>
    <input v-model="query" type="search" placeholder="Search by name" />
    <table>
      <thead>
        <tr>
          <th v-for="col in columns" :key="col" @click="sortBy(col)">
            {{ col }}
            <template v-if="sortKey === col">{{ sortDir === 1 ? '▲' : '▼' }}</template>
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
