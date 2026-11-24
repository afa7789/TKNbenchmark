import { useCallback, useEffect, useState } from "react";

export default function KvBrowser({ baseUrl }) {
  const [keys, setKeys] = useState([]);
  const [selected, setSelected] = useState(null);
  const [value, setValue] = useState("");
  const [form, setForm] = useState({ key: "", value: "" });
  const [error, setError] = useState(null);

  const request = useCallback(
    async (path, options) => {
      const res = await fetch(`${baseUrl}/kv${path}`, options);
      if (!res.ok) throw new Error(`${res.status} ${res.statusText}`);
      return res;
    },
    [baseUrl]
  );

  const loadKeys = useCallback(async () => {
    try {
      const res = await request("");
      setKeys(await res.json());
    } catch (err) {
      setError(err.message);
    }
  }, [request]);

  useEffect(() => {
    loadKeys();
  }, [loadKeys]);

  async function showValue(key) {
    setError(null);
    try {
      const res = await request(`/${encodeURIComponent(key)}`);
      setSelected(key);
      setValue(await res.text());
    } catch (err) {
      setError(err.message);
    }
  }

  async function handleSubmit(event) {
    event.preventDefault();
    if (!form.key) return;
    setError(null);
    try {
      await request(`/${encodeURIComponent(form.key)}`, { method: "PUT", body: form.value });
      if (selected === form.key) setValue(form.value);
      setForm({ key: "", value: "" });
    } catch (err) {
      setError(err.message);
    }
    await loadKeys();
  }

  async function remove(key) {
    setError(null);
    try {
      await request(`/${encodeURIComponent(key)}`, { method: "DELETE" });
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
      <form onSubmit={handleSubmit}>
        <input
          placeholder="Key"
          value={form.key}
          onChange={(e) => setForm((f) => ({ ...f, key: e.target.value }))}
        />
        <input
          placeholder="Value"
          value={form.value}
          onChange={(e) => setForm((f) => ({ ...f, value: e.target.value }))}
        />
        <button type="submit">Save</button>
      </form>
      <ul>
        {keys.map((key) => (
          <li key={key}>
            <button type="button" onClick={() => showValue(key)}>
              {key}
            </button>
            <button type="button" onClick={() => remove(key)}>
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
