import { useCart } from './CartContext.js'
import { formatMoney, useCurrency } from './CurrencyContext.js'

const TAX_RATE = 0.1

export default function Cart() {
  const { items, remove, setQuantity } = useCart()
  const currency = useCurrency()

  const subtotal = items.reduce((sum, item) => sum + item.price * item.quantity, 0)
  const tax = subtotal * TAX_RATE
  const total = subtotal + tax

  return (
    <section>
      <h2>Cart</h2>
      {items.length === 0 ? (
        <p>Your cart is empty</p>
      ) : (
        <ul>
          {items.map((item) => (
            <li key={item.id}>
              <span>{item.name}</span>{' '}
              <input
                type="number"
                min="1"
                aria-label={`Quantity for ${item.name}`}
                value={item.quantity}
                onChange={(event) => setQuantity(item.id, event.target.value)}
              />{' '}
              <span>{formatMoney(item.price * item.quantity, currency)}</span>{' '}
              <button type="button" onClick={() => remove(item.id)}>
                Remove
              </button>
            </li>
          ))}
        </ul>
      )}
      <p>Subtotal: {formatMoney(subtotal, currency)}</p>
      <p>Tax (10%): {formatMoney(tax, currency)}</p>
      <p>Total: {formatMoney(total, currency)}</p>
    </section>
  )
}
