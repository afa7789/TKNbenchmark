<script>
  import { cart } from './cart.svelte.js';
  import { getCurrency, formatMoney } from './currency.js';

  const TAX_RATE = 0.1;

  const currency = getCurrency();

  const tax = $derived(cart.subtotal * TAX_RATE);
  const total = $derived(cart.subtotal + tax);
</script>

<aside>
  <h2>Cart</h2>
  {#if cart.items.length}
    <ul>
      {#each cart.items as item (item.id)}
        <li>
          <span>{item.name}</span>
          <input
            type="number"
            min="1"
            aria-label="Quantity for {item.name}"
            bind:value={() => item.quantity, (v) => cart.setQuantity(item.id, v)}
          />
          <span>{formatMoney(item.price * item.quantity, currency)}</span>
          <button type="button" onclick={() => cart.remove(item.id)}>Remove</button>
        </li>
      {/each}
    </ul>
  {:else}
    <p>Your cart is empty</p>
  {/if}
  <dl>
    <dt>Subtotal</dt>
    <dd>{formatMoney(cart.subtotal, currency)}</dd>
    <dt>Tax (10%)</dt>
    <dd>{formatMoney(tax, currency)}</dd>
    <dt>Total</dt>
    <dd>{formatMoney(total, currency)}</dd>
  </dl>
</aside>
