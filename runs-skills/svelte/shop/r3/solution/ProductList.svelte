<script>
  import { cart } from './cart.svelte.js';
  import SearchBox from './SearchBox.svelte';
  import ProductItem from './ProductItem.svelte';

  let { products } = $props();

  let query = $state('');
  let category = $state('');

  const categories = $derived([...new Set(products.map((product) => product.category))]);

  const filtered = $derived.by(() => {
    const q = query.trim().toLowerCase();
    return products.filter(
      (product) =>
        (!category || product.category === category) &&
        (!q || product.name.toLowerCase().includes(q))
    );
  });
</script>

<section>
  <SearchBox onsearch={(q) => (query = q)} />
  <select bind:value={category} aria-label="Category">
    <option value="">All categories</option>
    {#each categories as c (c)}
      <option value={c}>{c}</option>
    {/each}
  </select>

  <ul>
    {#each filtered as product (product.id)}
      <ProductItem {product} onadd={cart.add} />
    {:else}
      <li>No products</li>
    {/each}
  </ul>
</section>
