<script>
  import { cart } from './cart.svelte.js';
  import SearchBox from './SearchBox.svelte';
  import ProductItem from './ProductItem.svelte';

  let { products } = $props();

  let query = $state('');
  let category = $state('all');

  const categories = $derived([...new Set(products.map((p) => p.category))]);

  const filtered = $derived.by(() => {
    const q = query.trim().toLowerCase();
    return products.filter(
      (p) => (category === 'all' || p.category === category) && p.name.toLowerCase().includes(q)
    );
  });
</script>

<section>
  <SearchBox onsearch={(q) => (query = q)} />
  <select bind:value={category}>
    <option value="all">All categories</option>
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
