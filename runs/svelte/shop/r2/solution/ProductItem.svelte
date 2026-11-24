<script>
  import { getCurrency } from './currency.js';

  let { product, onadd } = $props();
  const currency = getCurrency();
  const price = $derived(
    new Intl.NumberFormat(undefined, { style: 'currency', currency }).format(product.price)
  );
</script>

<li>
  <span>{product.name}</span>
  <span>{product.category}</span>
  <span>{price}</span>
  <button type="button" onclick={() => onadd(product)}>Add</button>
</li>
