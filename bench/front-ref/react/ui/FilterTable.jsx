import { useState } from 'react'
export default function FilterTable({ rows }) {
  const [q, setQ] = useState('')
  const [sort, setSort] = useState({ key: 'name', dir: 1 })
  const shown = rows.filter((r) => r.name.toLowerCase().includes(q.toLowerCase())).sort((a, b) => (a[sort.key] > b[sort.key] ? sort.dir : -sort.dir))
  const by = (key) => setSort({ key, dir: sort.key === key ? -sort.dir : 1 })
  return (
    <div>
      <input value={q} onChange={(e) => setQ(e.target.value)} />
      <table>
        <thead><tr>{['name', 'price', 'qty'].map((k) => <th key={k} onClick={() => by(k)}>{k}</th>)}</tr></thead>
        <tbody>{shown.map((r) => <tr key={r.name}><td>{r.name}</td><td>{r.price}</td><td>{r.qty}</td></tr>)}</tbody>
        <tfoot><tr><td>Total {shown.reduce((s, r) => s + r.price * r.qty, 0)}</td></tr></tfoot>
      </table>
    </div>
  )
}
