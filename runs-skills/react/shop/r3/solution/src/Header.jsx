import { useCart } from './CartContext.js'

export default function Header({ onCheckout }) {
  const { items } = useCart()
  const count = items.reduce((sum, item) => sum + item.quantity, 0)

  return (
    <header>
      <h1>Shop</h1>
      <span>Cart: {count} {count === 1 ? 'item' : 'items'}</span>
      <button type="button" onClick={onCheckout}>
        Checkout
      </button>
    </header>
  )
}
