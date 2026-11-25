<script>
  import { cart } from './cart.svelte.js';

  let { oncheckout } = $props();
</script>

<header>
  <h1>Shop</h1>
  <span>Cart: {cart.count} {cart.count === 1 ? 'item' : 'items'}</span>
  <button onclick={oncheckout}>Checkout</button>
</header>
