<script>
  import { getCurrency, formatPrice } from './currency.js';

  let { product, onadd } = $props();

  const currency = getCurrency();
</script>

<li>
  <span>{product.name}</span>
  <span>{formatPrice(product.price, currency)}</span>
  <button type="button" onclick={() => onadd(product)}>Add</button>
</li>
