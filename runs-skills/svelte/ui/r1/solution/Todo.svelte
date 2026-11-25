<script>
  let text = $state('');
  let items = $state([]);
  let nextId = 0;

  function add(e) {
    e.preventDefault();
    const value = text.trim();
    if (!value) return;
    items.push({ id: nextId++, text: value });
    text = '';
  }

  function remove(id) {
    items = items.filter((item) => item.id !== id);
  }
</script>

<form onsubmit={add}>
  <input bind:value={text} />
  <button type="submit">Add</button>
</form>
<ul>
  {#each items as item (item.id)}
    <li>
      {item.text}
      <button onclick={() => remove(item.id)}>Remove</button>
    </li>
  {/each}
</ul>
