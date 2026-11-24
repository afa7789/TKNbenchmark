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
    [baseUrl]
  );

  const loadKeys = useCallback(async () => {
    try {
      const res = await request("/kv");
      setKeys(await res.json());
    } catch (err) {
      setError(err.message);
    }
  }, [request]);

  useEffect(() => {
    loadKeys();
  }, [loadKeys]);

  async function showKey(key) {
    setError(null);
    try {
      const res = await request(`/kv/${encodeURIComponent(key)}`);
      setValue(await res.text());
      setSelected(key);
    } catch (err) {
      setError(err.message);
    }
  }

  async function handleSave(e) {
    e.preventDefault();
    if (!newKey) return;
    setError(null);
    try {
      await request(`/kv/${encodeURIComponent(newKey)}`, { method: "PUT", body: newValue });
      if (selected === newKey) setValue(newValue);
      setNewKey("");
      setNewValue("");
    } catch (err) {
      setError(err.message);
    }
    await loadKeys();
  }

  async function handleDelete(key) {
    setError(null);
    try {
      await request(`/kv/${encodeURIComponent(key)}`, { method: "DELETE" });
      if (selected === key) {
        setSelected(null);
        setValue("");
      }
    } catch (err) {
      setError(err.message);
    }
    await loadKeys();
  }

  return (
    <div>
      {error && <p role="alert">Error: {error}</p>}
      <ul>
        {keys.map((key) => (
          <li key={key}>
            <button type="button" onClick={() => showKey(key)}>
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
      <form onSubmit={handleSave}>
        <input value={newKey} onChange={(e) => setNewKey(e.target.value)} placeholder="Key" />
        <input value={newValue} onChange={(e) => setNewValue(e.target.value)} placeholder="Value" />
        <button type="submit">Save</button>
      </form>
    </div>
  );
}
