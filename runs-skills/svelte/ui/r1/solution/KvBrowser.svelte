<script>
  import { onMount } from 'svelte';

  let { baseUrl } = $props();

  let keys = $state.raw([]);
  let selected = $state(null);
  let value = $state('');
  let newKey = $state('');
  let newValue = $state('');
  let error = $state(null);

  const url = (key) => `${baseUrl}/kv${key === undefined ? '' : `/${encodeURIComponent(key)}`}`;

  async function request(path, options) {
    const res = await fetch(path, options);
    if (!res.ok) throw new Error(`${res.status} ${res.statusText}`);
    return res;
  }

  async function run(action) {
    error = null;
    try {
      await action();
    } catch (err) {
      error = err.message;
    }
  }

  const load = () =>
    run(async () => {
      keys = await (await request(url())).json();
    });

  const show = (key) =>
    run(async () => {
      value = await (await request(url(key))).text();
      selected = key;
    });

  const save = (e) => {
    e.preventDefault();
    if (!newKey) return;
    return run(async () => {
      await request(url(newKey), { method: 'PUT', body: newValue });
      if (selected === newKey) value = newValue;
      newKey = '';
      newValue = '';
      await load();
    });
  };

  const remove = (key) =>
    run(async () => {
      await request(url(key), { method: 'DELETE' });
      if (selected === key) selected = null;
      await load();
    });

  onMount(load);
</script>

{#if error}
  <p role="alert">Error: {error}</p>
{/if}

<form onsubmit={save}>
  <input placeholder="Key" bind:value={newKey} />
  <input placeholder="Value" bind:value={newValue} />
  <button type="submit">Save</button>
</form>

<ul>
  {#each keys as key (key)}
    <li>
      <button onclick={() => show(key)}>{key}</button>
      <button onclick={() => remove(key)}>Delete</button>
    </li>
  {/each}
</ul>

{#if selected !== null}
  <h2>{selected}</h2>
  <pre>{value}</pre>
{/if}
