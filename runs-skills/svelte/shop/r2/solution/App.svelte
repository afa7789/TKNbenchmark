<script>
  import { setCurrency } from './currency.js';
  import Header from './Header.svelte';
  import ProductList from './ProductList.svelte';
  import Cart from './Cart.svelte';
  import Modal from './Modal.svelte';
  import CheckoutForm from './CheckoutForm.svelte';

  let { products } = $props();

  setCurrency('USD');

  let checkoutOpen = $state(false);
</script>

<Header oncheckout={() => (checkoutOpen = true)} />
<main>
  <ProductList {products} />
  <Cart />
</main>

{#if checkoutOpen}
  <Modal title="Checkout" onclose={() => (checkoutOpen = false)}>
    <CheckoutForm onsubmitted={() => (checkoutOpen = false)} />
  </Modal>
{/if}
