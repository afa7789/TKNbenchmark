<script>
  let { rows = [] } = $props();

  const columns = ['name', 'price', 'qty'];

  let query = $state('');
  let sortKey = $state(null);
  let sortDir = $state(1);

  const visible = $derived.by(() => {
    const q = query.toLowerCase();
    const filtered = rows.filter((row) => row.name.toLowerCase().includes(q));
    if (!sortKey) return filtered;
    return filtered.toSorted((a, b) => {
      const x = a[sortKey];
      const y = b[sortKey];
      const cmp = typeof x === 'string' ? x.localeCompare(y) : x - y;
      return cmp * sortDir;
    });
  });

  const total = $derived(visible.reduce((sum, row) => sum + row.price * row.qty, 0));

  function sortBy(key) {
    if (sortKey === key) {
      sortDir = -sortDir;
    } else {
      sortKey = key;
      sortDir = 1;
    }
  }
</script>

<input type="search" placeholder="Search" bind:value={query} />
<table>
  <thead>
    <tr>
      {#each columns as column}
        <th onclick={() => sortBy(column)}>
          {column}{sortKey === column ? (sortDir === 1 ? ' ▲' : ' ▼') : ''}
        </th>
      {/each}
    </tr>
  </thead>
  <tbody>
    {#each visible as row, i (row.name + i)}
      <tr>
        <td>{row.name}</td>
        <td>{row.price}</td>
        <td>{row.qty}</td>
      </tr>
    {/each}
  </tbody>
  <tfoot>
    <tr>
      <td colspan="2">Total</td>
      <td>{total}</td>
    </tr>
  </tfoot>
</table>
