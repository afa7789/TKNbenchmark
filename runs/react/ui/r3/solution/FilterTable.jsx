import { useMemo, useState } from "react";

const columns = [
  { key: "name", label: "Name" },
  { key: "price", label: "Price" },
  { key: "qty", label: "Qty" },
];

export default function FilterTable({ rows = [] }) {
  const [query, setQuery] = useState("");
  const [sort, setSort] = useState({ key: null, dir: 1 });

  const visible = useMemo(() => {
    const q = query.toLowerCase();
    const filtered = rows.filter((row) => row.name.toLowerCase().includes(q));
    if (!sort.key) return filtered;
    return filtered.toSorted((a, b) => {
      const x = a[sort.key];
      const y = b[sort.key];
      const cmp = typeof x === "string" ? x.localeCompare(y) : x - y;
      return cmp * sort.dir;
    });
  }, [rows, query, sort]);

  const total = visible.reduce((sum, row) => sum + row.price * row.qty, 0);

  function toggleSort(key) {
    setSort((prev) => ({ key, dir: prev.key === key ? -prev.dir : 1 }));
  }

  return (
    <div>
      <input
        type="search"
        placeholder="Search"
        value={query}
        onChange={(e) => setQuery(e.target.value)}
      />
      <table>
        <thead>
          <tr>
            {columns.map((col) => (
              <th key={col.key} onClick={() => toggleSort(col.key)}>
                {col.label}
                {sort.key === col.key && (sort.dir === 1 ? " ▲" : " ▼")}
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {visible.map((row, i) => (
            <tr key={`${row.name}-${i}`}>
              <td>{row.name}</td>
              <td>{row.price}</td>
              <td>{row.qty}</td>
            </tr>
          ))}
        </tbody>
        <tfoot>
          <tr>
            <td colSpan={2}>Total</td>
            <td>{total}</td>
          </tr>
        </tfoot>
      </table>
    </div>
  );
}
