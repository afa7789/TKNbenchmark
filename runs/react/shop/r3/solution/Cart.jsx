import { useCart } from "./CartContext.jsx";
import { useFormatPrice } from "./CurrencyContext.jsx";

const TAX_RATE = 0.1;

export default function Cart() {
  const { items, remove, setQuantity } = useCart();
  const formatPrice = useFormatPrice();

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
                min="1"
                aria-label={`Quantity of ${item.name}`}
                value={item.quantity}
                onChange={(event) => setQuantity(item.id, event.target.valueAsNumber)}
              />{" "}
              <span>{formatPrice(item.price * item.quantity)}</span>{" "}
              <button type="button" onClick={() => remove(item.id)}>
                Remove
              </button>
            </li>
          ))}
        </ul>
      )}
      <dl>
        <dt>Subtotal</dt>
        <dd>{formatPrice(subtotal)}</dd>
        <dt>Tax (10%)</dt>
        <dd>{formatPrice(tax)}</dd>
        <dt>Total</dt>
        <dd>{formatPrice(total)}</dd>
      </dl>
    </section>
  );
}
