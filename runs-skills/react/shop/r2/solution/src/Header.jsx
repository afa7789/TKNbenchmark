import { useCart } from './CartContext.js'

export default function Header({ onCheckout }) {
  const { count } = useCart()

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
