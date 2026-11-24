<script>
  import { cart } from './cart.svelte.js';
  import { getCurrency, formatMoney } from './currency.js';

  const TAX_RATE = 0.1;

  const currency = getCurrency();

  const subtotal = $derived(cart.subtotal);
  const tax = $derived(subtotal * TAX_RATE);
  const total = $derived(subtotal + tax);
</script>

<section>
  <h2>Cart</h2>
  {#if cart.items.length}
    <ul>
      {#each cart.items as item (item.id)}
        <li>
          <span>{item.name}</span>
          <input
            type="number"
            min="1"
            bind:value={() => item.quantity, (value) => cart.setQuantity(item.id, value)}
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
    <dd>{formatMoney(subtotal, currency)}</dd>
    <dt>Tax (10%)</dt>
    <dd>{formatMoney(tax, currency)}</dd>
    <dt>Total</dt>
    <dd>{formatMoney(total, currency)}</dd>
  </dl>
</section>
