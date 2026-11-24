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
  <SearchBox onsearch={(value) => (query = value)} />
  <select bind:value={category}>
    <option value="">All categories</option>
    {#each categories as c (c)}
      <option value={c}>{c}</option>
    {/each}
  </select>

  {#if filtered.length}
    <ul>
      {#each filtered as product (product.id)}
        <ProductItem {product} onadd={(p) => cart.add(p)} />
      {/each}
    </ul>
  {:else}
    <p>No products</p>
  {/if}
</section>
