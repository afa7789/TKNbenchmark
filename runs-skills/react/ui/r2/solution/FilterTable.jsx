import { useState } from 'react'

const columns = [
  { key: 'name', label: 'Name' },
  { key: 'price', label: 'Price' },
  { key: 'qty', label: 'Qty' },
]

function compare(a, b) {
  if (typeof a === 'string' && typeof b === 'string') return a.localeCompare(b)
  return a < b ? -1 : a > b ? 1 : 0
}

export default function FilterTable({ rows = [] }) {
  const [query, setQuery] = useState('')
  const [sort, setSort] = useState({ key: null, asc: true })

  const needle = query.toLowerCase()
  const filtered = rows.filter(row => row.name.toLowerCase().includes(needle))
  const visible = sort.key
    ? filtered.toSorted((a, b) => {
        const result = compare(a[sort.key], b[sort.key])
        return sort.asc ? result : -result
      })
    : filtered
  const total = visible.reduce((sum, row) => sum + row.price * row.qty, 0)

  function handleSort(key) {
    setSort(prev => (prev.key === key ? { key, asc: !prev.asc } : { key, asc: true }))
  }

  return (
    <div>
      <input
        type="search"
        placeholder="Search by name"
        value={query}
        onChange={e => setQuery(e.target.value)}
      />
      <table>
        <thead>
          <tr>
            {columns.map(col => (
              <th
                key={col.key}
                onClick={() => handleSort(col.key)}
                aria-sort={sort.key === col.key ? (sort.asc ? 'ascending' : 'descending') : 'none'}
              >
                {col.label}
                {sort.key === col.key && (sort.asc ? ' ▲' : ' ▼')}
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {visible.map((row, i) => (
            <tr key={`${row.name}-${i}`}>
              <td>{row.name}</td>
              <td>{row.price}</td>
              <td>{row.qty}</td>
            </tr>
          ))}
        </tbody>
        <tfoot>
          <tr>
            <td colSpan={2}>Total</td>
            <td>{total}</td>
          </tr>
        </tfoot>
      </table>
    </div>
  )
}
