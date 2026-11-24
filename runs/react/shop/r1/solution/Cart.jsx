import { useCart } from "./CartContext.jsx";
import { formatMoney, useCurrency } from "./CurrencyContext.jsx";

const TAX_RATE = 0.1;

export default function Cart() {
  const { items, remove, setQuantity } = useCart();
  const currency = useCurrency();

  const subtotal = items.reduce((sum, item) => sum + item.price * item.quantity, 0);
  const tax = subtotal * TAX_RATE;
  const total = subtotal + tax;

  return (
    <section>
      <h2>Cart</h2>
      {items.length === 0 ? (
        <p>Your cart is empty</p>
      ) : (
        <ul>
          {items.map((item) => (
            <li key={item.id}>
              <span>{item.name}</span>{" "}
              <input
                type="number"
                min="0"
                aria-label={`Quantity of ${item.name}`}
                value={item.quantity}
                onChange={(event) => setQuantity(item.id, event.target.value)}
              />{" "}
              <span>{formatMoney(item.price * item.quantity, currency)}</span>{" "}
              <button type="button" onClick={() => remove(item.id)}>
                Remove
              </button>
            </li>
          ))}
        </ul>
      )}
      <dl>
        <dt>Subtotal</dt>
        <dd>{formatMoney(subtotal, currency)}</dd>
        <dt>Tax (10%)</dt>
        <dd>{formatMoney(tax, currency)}</dd>
        <dt>Total</dt>
        <dd>{formatMoney(total, currency)}</dd>
      </dl>
    </section>
  );
}
