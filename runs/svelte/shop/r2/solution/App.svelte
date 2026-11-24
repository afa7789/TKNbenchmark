<script>
  import { setCurrency } from './currency.js';
  import Header from './Header.svelte';
  import ProductList from './ProductList.svelte';
  import Cart from './Cart.svelte';
  import Modal from './Modal.svelte';
  import CheckoutForm from './CheckoutForm.svelte';

  let { products } = $props();
  let checkoutOpen = $state(false);

  setCurrency('USD');
</script>

<Header oncheckout={() => (checkoutOpen = true)} />
<ProductList {products} />
<Cart />

{#if checkoutOpen}
  <Modal onclose={() => (checkoutOpen = false)}>
    <CheckoutForm onsubmitted={() => (checkoutOpen = false)} />
  </Modal>
{/if}
