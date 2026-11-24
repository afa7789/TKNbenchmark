<script>
  let users = $state([]);
  let loading = $state(true);
  let error = $state(null);

  $effect(() => {
    const controller = new AbortController();

    fetch('https://jsonplaceholder.typicode.com/users', { signal: controller.signal })
      .then((res) => {
        if (!res.ok) throw new Error(`HTTP ${res.status}`);
        return res.json();
      })
      .then((data) => {
        users = data;
        loading = false;
      })
      .catch((err) => {
        if (err.name === 'AbortError') return;
        error = err.message;
        loading = false;
      });

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
