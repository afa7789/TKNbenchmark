import { useState } from 'react'
import { useCart } from './CartContext.js'
import SearchBox from './SearchBox.jsx'
import ProductItem from './ProductItem.jsx'

export default function ProductList({ products }) {
  const { add } = useCart()
  const [query, setQuery] = useState('')
  const [category, setCategory] = useState('all')

  const categories = [...new Set(products.map(product => product.category))]
  const normalizedQuery = query.trim().toLowerCase()
  const visible = products.filter(
    product =>
      (category === 'all' || product.category === category) &&
      product.name.toLowerCase().includes(normalizedQuery)
  )

  return (
    <section>
      <h2>Products</h2>
      <SearchBox onSearch={setQuery} />
      <select aria-label="Category" value={category} onChange={e => setCategory(e.target.value)}>
        <option value="all">All categories</option>
        {categories.map(c => (
          <option key={c} value={c}>{c}</option>
        ))}
      </select>
      {visible.length === 0 ? (
        <p>No products</p>
      ) : (
        <ul>
          {visible.map(product => (
            <ProductItem key={product.id} product={product} onAdd={add} />
          ))}
        </ul>
      )}
    </section>
  )
}
