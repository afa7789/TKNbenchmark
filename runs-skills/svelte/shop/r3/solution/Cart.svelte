<script>
  import { cart } from './cart.svelte.js';
  import { getCurrency } from './currency.js';

  const currency = getCurrency();
  const formatter = new Intl.NumberFormat('en-US', { style: 'currency', currency });

  const subtotal = $derived(cart.items.reduce((sum, item) => sum + item.price * item.quantity, 0));
  const tax = $derived(subtotal * 0.1);
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
          <span>{formatter.format(item.price)}</span>
          <input
            type="number"
            min="1"
            aria-label="Quantity of {item.name}"
            bind:value={() => item.quantity, (quantity) => cart.setQuantity(item.id, quantity)}
          />
          <button type="button" onclick={() => cart.remove(item.id)}>Remove</button>
        </li>
      {/each}
    </ul>
  {/if}
  <dl>
    <dt>Subtotal</dt>
    <dd>{formatter.format(subtotal)}</dd>
    <dt>Tax (10%)</dt>
    <dd>{formatter.format(tax)}</dd>
    <dt>Total</dt>
    <dd>{formatter.format(total)}</dd>
  </dl>
</section>
