import { useEffect, useState } from 'react'
import { useCart } from './cart.js'
function SearchBox({ onSearch }) {
  const [v, setV] = useState('')
  useEffect(() => { const t = setTimeout(() => onSearch(v), 300); return () => clearTimeout(t) }, [v])
  return <input type="search" value={v} onChange={(e) => setV(e.target.value)} />
}
export default function ProductList({ products }) {
  const [q, setQ] = useState('')
  const { add } = useCart()
  const shown = products.filter((p) => p.name.toLowerCase().includes(q.toLowerCase()))
  return <div><SearchBox onSearch={setQ} />{shown.length ? <ul>{shown.map((p) => <li key={p.id}>{p.name}<button onClick={() => add(p)}>Add</button></li>)}</ul> : <p>No products</p>}</div>
}
