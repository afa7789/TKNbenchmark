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
  {#if cart.items.length === 0}
    <p>Your cart is empty</p>
  {:else}
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
          <button onclick={() => cart.remove(item.id)}>Remove</button>
        </li>
      {/each}
    </ul>
  {/if}
  <p>Subtotal: {formatMoney(subtotal, currency)}</p>
  <p>Tax (10%): {formatMoney(tax, currency)}</p>
  <p>Total: {formatMoney(total, currency)}</p>
</section>
