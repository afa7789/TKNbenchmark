import { useMemo, useState } from "react";

const COLUMNS = ["name", "price", "qty"];

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
    setSort((prev) => (prev.key === key ? { key, dir: -prev.dir } : { key, dir: 1 }));
  }

  return (
    <div>
      <input type="search" value={query} onChange={(e) => setQuery(e.target.value)} placeholder="Search" />
      <table>
        <thead>
          <tr>
            {COLUMNS.map((col) => (
              <th key={col} onClick={() => toggleSort(col)}>
                {col}
                {sort.key === col && (sort.dir === 1 ? " ▲" : " ▼")}
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
