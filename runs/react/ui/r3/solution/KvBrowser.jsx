import { useCallback, useEffect, useState } from "react";

export default function KvBrowser({ baseUrl }) {
  const [keys, setKeys] = useState([]);
  const [selected, setSelected] = useState(null);
  const [value, setValue] = useState("");
  const [newKey, setNewKey] = useState("");
  const [newValue, setNewValue] = useState("");
  const [error, setError] = useState(null);

  const request = useCallback(
    async (path, options) => {
      const res = await fetch(`${baseUrl}${path}`, options);
      if (!res.ok) throw new Error(`${res.status} ${res.statusText}`);
      return res;
    },
    [baseUrl],
  );

  const run = useCallback(async (action) => {
    try {
      setError(null);
      await action();
    } catch (err) {
      setError(err.message);
    }
  }, []);

  const loadKeys = useCallback(async () => {
    const res = await request("/kv");
    setKeys(await res.json());
  }, [request]);

  useEffect(() => {
    run(loadKeys);
  }, [run, loadKeys]);

  function showValue(key) {
    run(async () => {
      const res = await request(`/kv/${encodeURIComponent(key)}`);
      setValue(await res.text());
      setSelected(key);
    });
  }

  function handleSave(event) {
    event.preventDefault();
    if (!newKey) return;
    run(async () => {
      await request(`/kv/${encodeURIComponent(newKey)}`, { method: "PUT", body: newValue });
      if (selected === newKey) setValue(newValue);
      setNewKey("");
      setNewValue("");
      await loadKeys();
    });
  }

  function handleDelete(key) {
    run(async () => {
      await request(`/kv/${encodeURIComponent(key)}`, { method: "DELETE" });
      if (selected === key) {
        setSelected(null);
        setValue("");
      }
      await loadKeys();
    });
  }

  return (
    <div>
      {error && <p role="alert">Error: {error}</p>}
      <form onSubmit={handleSave}>
        <input placeholder="Key" value={newKey} onChange={(e) => setNewKey(e.target.value)} />
        <input placeholder="Value" value={newValue} onChange={(e) => setNewValue(e.target.value)} />
        <button type="submit">Save</button>
      </form>
      <ul>
        {keys.map((key) => (
          <li key={key}>
            <button type="button" onClick={() => showValue(key)}>
              {key}
            </button>
            <button type="button" onClick={() => handleDelete(key)}>
              Delete
            </button>
          </li>
        ))}
      </ul>
      {selected !== null && (
        <div>
          <h3>{selected}</h3>
          <pre>{value}</pre>
        </div>
      )}
    </div>
  );
}
