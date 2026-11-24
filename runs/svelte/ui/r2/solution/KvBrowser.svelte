<script>
  let { baseUrl } = $props();

  let keys = $state([]);
  let selected = $state(null);
  let selectedValue = $state('');
  let newKey = $state('');
  let newValue = $state('');
  let error = $state(null);

  async function request(path, options) {
    const res = await fetch(`${baseUrl}/kv${path}`, options);
    if (!res.ok) throw new Error(`${res.status} ${res.statusText}`);
    return res;
  }

  async function run(action) {
    try {
      error = null;
      await action();
    } catch (err) {
      error = err.message;
    }
  }

  function loadKeys() {
    return run(async () => {
      keys = await (await request('')).json();
    });
  }

  function show(key) {
    return run(async () => {
      selectedValue = await (await request(`/${encodeURIComponent(key)}`)).text();
      selected = key;
    });
  }

  function save(event) {
    event.preventDefault();
    if (!newKey) return;
    return run(async () => {
      await request(`/${encodeURIComponent(newKey)}`, { method: 'PUT', body: newValue });
      if (selected === newKey) selectedValue = newValue;
      newKey = '';
      newValue = '';
      await loadKeys();
    });
  }

  function remove(key) {
    return run(async () => {
      await request(`/${encodeURIComponent(key)}`, { method: 'DELETE' });
      if (selected === key) selected = null;
      await loadKeys();
    });
  }

  $effect(() => {
    baseUrl;
    loadKeys();
  });
</script>

{#if error}
  <p>Error: {error}</p>
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
  <h3>{selected}</h3>
  <pre>{selectedValue}</pre>
{/if}
