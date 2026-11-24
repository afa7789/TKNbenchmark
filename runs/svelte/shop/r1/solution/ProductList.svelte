<script>
  import { cart } from './cart.svelte.js';
  import SearchBox from './SearchBox.svelte';
  import ProductItem from './ProductItem.svelte';

  let { products } = $props();

  let query = $state('');
  let category = $state('all');

  const categories = $derived([...new Set(products.map((product) => product.category))]);

  const filtered = $derived(
    products.filter((product) => {
      const matchesQuery = product.name.toLowerCase().includes(query.trim().toLowerCase());
      const matchesCategory = category === 'all' || product.category === category;
      return matchesQuery && matchesCategory;
    })
  );
</script>

<section>
  <SearchBox onsearch={(value) => (query = value)} />
  <select bind:value={category}>
    <option value="all">All categories</option>
    {#each categories as c (c)}
      <option value={c}>{c}</option>
    {/each}
  </select>

  {#if filtered.length === 0}
    <p>No products</p>
  {:else}
    <ul>
      {#each filtered as product (product.id)}
        <ProductItem {product} onadd={(p) => cart.add(p)} />
      {/each}
    </ul>
  {/if}
</section>
