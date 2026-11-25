import { useState } from 'react'

const columns = [
  { key: 'name', label: 'Name' },
  { key: 'price', label: 'Price' },
  { key: 'qty', label: 'Qty' },
]

export default function FilterTable({ rows = [] }) {
  const [query, setQuery] = useState('')
  const [sort, setSort] = useState({ key: null, asc: true })

  const needle = query.trim().toLowerCase()
  const visible = rows.filter(row => row.name.toLowerCase().includes(needle))

  if (sort.key) {
    const dir = sort.asc ? 1 : -1
    visible.sort((a, b) => {
      const x = a[sort.key]
      const y = b[sort.key]
      const cmp = typeof x === 'string' ? x.localeCompare(y) : x - y
      return cmp * dir
    })
  }

  const total = visible.reduce((sum, row) => sum + row.price * row.qty, 0)

  function toggleSort(key) {
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
                onClick={() => toggleSort(col.key)}
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
