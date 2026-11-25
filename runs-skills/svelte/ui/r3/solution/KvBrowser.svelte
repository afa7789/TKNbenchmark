<script>
  import { onMount } from 'svelte';

  let { baseUrl } = $props();

  let keys = $state.raw([]);
  let selected = $state(null);
  let selectedValue = $state('');
  let newKey = $state('');
  let newValue = $state('');
  let error = $state(null);

  const url = (key) => `${baseUrl}/kv${key === undefined ? '' : `/${encodeURIComponent(key)}`}`;

  async function request(key, options) {
    const res = await fetch(url(key), options);
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
      keys = await (await request()).json();
    });

  const show = (key) =>
    run(async () => {
      selectedValue = await (await request(key)).text();
      selected = key;
    });

  const save = (e) => {
    e.preventDefault();
    if (!newKey) return;
    return run(async () => {
      await request(newKey, { method: 'PUT', body: newValue });
      if (selected === newKey) selectedValue = newValue;
      newKey = '';
      newValue = '';
      keys = await (await request()).json();
    });
  };

  const remove = (key) =>
    run(async () => {
      await request(key, { method: 'DELETE' });
      if (selected === key) selected = null;
      keys = await (await request()).json();
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
  <section>
    <h3>{selected}</h3>
    <pre>{selectedValue}</pre>
  </section>
{/if}
