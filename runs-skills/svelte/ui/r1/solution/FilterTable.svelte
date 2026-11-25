<script>
  let { rows = [] } = $props();

  const columns = ['name', 'price', 'qty'];

  let query = $state('');
  let sortKey = $state(null);
  let ascending = $state(true);

  let visible = $derived.by(() => {
    const q = query.toLowerCase();
    const filtered = rows.filter((row) => row.name.toLowerCase().includes(q));
    if (!sortKey) return filtered;
    const dir = ascending ? 1 : -1;
    return filtered.toSorted((a, b) => {
      const x = a[sortKey];
      const y = b[sortKey];
      if (typeof x === 'string') return x.localeCompare(y) * dir;
      return (x - y) * dir;
    });
  });

  let total = $derived(visible.reduce((sum, row) => sum + row.price * row.qty, 0));

  function sortBy(key) {
    if (sortKey === key) {
      ascending = !ascending;
    } else {
      sortKey = key;
      ascending = true;
    }
  }
</script>

<input type="search" placeholder="Search by name" bind:value={query} />
<table>
  <thead>
    <tr>
      {#each columns as column (column)}
        <th onclick={() => sortBy(column)}>
          {column}{sortKey === column ? (ascending ? ' ▲' : ' ▼') : ''}
        </th>
      {/each}
    </tr>
  </thead>
  <tbody>
    {#each visible as row (row)}
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
