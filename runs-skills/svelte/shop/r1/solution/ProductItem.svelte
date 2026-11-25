<script>
  import { getCurrency, formatMoney } from './currency.js';

  let { product, onadd } = $props();

  const currency = getCurrency();
</script>

<li>
  <span>{product.name}</span>
  <span>{product.category}</span>
  <span>{formatMoney(product.price, currency)}</span>
  <button onclick={() => onadd(product)}>Add</button>
</li>
