<script>
  import { onDestroy } from 'svelte';

  let { onsearch, delay = 300 } = $props();

  let value = $state('');
  let timer;

  function handleInput(event) {
    value = event.currentTarget.value;
    clearTimeout(timer);
    timer = setTimeout(() => onsearch(value), delay);
  }

  onDestroy(() => clearTimeout(timer));
</script>

<input type="search" placeholder="Search products" aria-label="Search products" {value} oninput={handleInput} />
