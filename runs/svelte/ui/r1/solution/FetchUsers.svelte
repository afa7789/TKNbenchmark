<script>
  import { onMount } from 'svelte';

  let users = $state([]);
  let loading = $state(true);
  let error = $state(null);

  onMount(() => {
    const controller = new AbortController();

    (async () => {
      try {
        const res = await fetch('https://jsonplaceholder.typicode.com/users', {
          signal: controller.signal
        });
        if (!res.ok) throw new Error(`HTTP ${res.status}`);
        users = await res.json();
      } catch (e) {
        if (e.name !== 'AbortError') error = e.message;
      } finally {
        loading = false;
      }
    })();

    return () => controller.abort();
  });
</script>

{#if loading}
  <p>Loading…</p>
{:else if error}
  <p>Error: {error}</p>
{:else}
  <ul>
    {#each users as user (user.id)}
      <li>{user.name}</li>
    {/each}
  </ul>
{/if}
