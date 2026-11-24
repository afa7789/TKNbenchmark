<script>
  import { cart } from './cart.svelte.js';
  import { getCurrency, formatPrice } from './currency.js';

  const TAX_RATE = 0.1;

  const currency = getCurrency();

  const subtotal = $derived(cart.items.reduce((sum, item) => sum + item.price * item.quantity, 0));
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
            bind:value={() => item.quantity, (value) => cart.setQuantity(item.id, value)}
          />
          <span>{formatPrice(item.price * item.quantity, currency)}</span>
          <button type="button" onclick={() => cart.remove(item.id)}>Remove</button>
        </li>
      {/each}
    </ul>
  {/if}
  <p>Subtotal: {formatPrice(subtotal, currency)}</p>
  <p>Tax (10%): {formatPrice(tax, currency)}</p>
  <p>Total: {formatPrice(total, currency)}</p>
</section>
