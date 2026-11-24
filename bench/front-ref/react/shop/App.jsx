import { useState } from 'react'
import { CartContext, CurrencyContext } from './cart.js'
import ProductList from './ProductList.jsx'
export default function App({ products }) {
  const [items, setItems] = useState([])
  const add = (p) => setItems((xs) => (xs.some((x) => x.id === p.id) ? xs.map((x) => (x.id === p.id ? { ...x, qty: x.qty + 1 } : x)) : [...xs, { ...p, qty: 1 }]))
  return (
    <CurrencyContext.Provider value="USD">
      <CartContext.Provider value={{ items, add }}>
        <header>Cart: {items.length}</header>
        <ProductList products={products} />
        <ul>{items.map((i) => <li key={i.id}>{i.name} × {i.qty}</li>)}</ul>
      </CartContext.Provider>
    </CurrencyContext.Provider>
  )
}
