import { useState } from 'react'
import { useCart } from './CartContext.js'
import SearchBox from './SearchBox.jsx'
import ProductItem from './ProductItem.jsx'

export default function ProductList({ products }) {
  const { add } = useCart()
  const [query, setQuery] = useState('')
  const [category, setCategory] = useState('')

  const categories = [...new Set(products.map((product) => product.category))]
  const normalizedQuery = query.trim().toLowerCase()
  const visibleProducts = products.filter(
    (product) =>
      (category === '' || product.category === category) &&
      product.name.toLowerCase().includes(normalizedQuery)
  )

  return (
    <section>
      <SearchBox onSearch={setQuery} />
      <select
        aria-label="Category"
        value={category}
        onChange={(event) => setCategory(event.target.value)}
      >
        <option value="">All categories</option>
        {categories.map((name) => (
          <option key={name} value={name}>
            {name}
          </option>
        ))}
      </select>
      {visibleProducts.length === 0 ? (
        <p>No products</p>
      ) : (
        <ul>
          {visibleProducts.map((product) => (
            <ProductItem key={product.id} product={product} onAdd={add} />
          ))}
        </ul>
      )}
    </section>
  )
}
