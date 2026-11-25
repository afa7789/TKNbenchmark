<script>
  import { onMount } from 'svelte';

  let users = $state.raw([]);
  let loading = $state(true);
  let error = $state(null);

  onMount(() => {
    const controller = new AbortController();
    fetch('https://jsonplaceholder.typicode.com/users', { signal: controller.signal })
      .then((res) => {
        if (!res.ok) throw new Error(`HTTP ${res.status}`);
        return res.json();
      })
      .then((data) => {
        users = data;
      })
      .catch((err) => {
        if (err.name !== 'AbortError') error = err;
      })
      .finally(() => {
        loading = false;
      });
    return () => controller.abort();
  });
</script>

{#if loading}
  <p>Loading…</p>
{:else if error}
  <p>Error: {error.message}</p>
{:else}
  <ul>
    {#each users as user (user.id)}
      <li>{user.name}</li>
    {/each}
  </ul>
{/if}
