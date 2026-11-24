<script>
  import { cart } from './cart.svelte.js';
  import { getCurrency } from './currency.js';

  const TAX_RATE = 0.1;
  const formatter = new Intl.NumberFormat(undefined, { style: 'currency', currency: getCurrency() });

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
            bind:value={() => item.quantity, (q) => cart.setQuantity(item.id, q)}
          />
          <span>{formatter.format(item.price * item.quantity)}</span>
          <button type="button" onclick={() => cart.remove(item.id)}>Remove</button>
        </li>
      {/each}
    </ul>
  {:else}
    <p>Your cart is empty</p>
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
