<script>
  let { onsearch, delay = 300 } = $props();

  let query = $state('');
  let timer;

  function handleInput() {
    clearTimeout(timer);
    timer = setTimeout(() => onsearch(query), delay);
  }

  $effect(() => {
    return () => clearTimeout(timer);
  });
</script>

<input type="search" placeholder="Search products" bind:value={query} oninput={handleInput} />
