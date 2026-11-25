<script>
  import { onDestroy } from 'svelte';

  let { onsearch, delay = 300 } = $props();

  let value = $state('');
  let timer;

  function handleInput() {
    clearTimeout(timer);
    timer = setTimeout(() => onsearch(value), delay);
  }

  onDestroy(() => clearTimeout(timer));
</script>

<input type="search" placeholder="Search products" bind:value oninput={handleInput} />
