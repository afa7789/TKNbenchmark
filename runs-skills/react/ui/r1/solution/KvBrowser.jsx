import { useEffect, useState } from 'react'

async function request(url, options) {
  const res = await fetch(url, options)
  if (!res.ok) throw new Error(`HTTP ${res.status}`)
  return res
}

export default function KvBrowser({ baseUrl }) {
  const [keys, setKeys] = useState([])
  const [version, setVersion] = useState(0)
  const [selected, setSelected] = useState(null)
  const [newKey, setNewKey] = useState('')
  const [newValue, setNewValue] = useState('')
  const [error, setError] = useState(null)

  const keyUrl = key => `${baseUrl}/kv/${encodeURIComponent(key)}`
  const reload = () => setVersion(v => v + 1)

  useEffect(() => {
    const controller = new AbortController()

    request(`${baseUrl}/kv`, { signal: controller.signal })
      .then(res => res.json())
      .then(setKeys)
      .catch(err => {
        if (err.name !== 'AbortError') setError(err.message)
      })

    return () => controller.abort()
  }, [baseUrl, version])

  async function show(key) {
    try {
      const res = await request(keyUrl(key))
      setSelected({ key, value: await res.text() })
      setError(null)
    } catch (err) {
      setError(err.message)
    }
  }

  async function handleSave(e) {
    e.preventDefault()
    if (!newKey) return
    try {
      await request(keyUrl(newKey), { method: 'PUT', body: newValue })
      setNewKey('')
      setNewValue('')
      setError(null)
    } catch (err) {
      setError(err.message)
    }
    reload()
  }

  async function remove(key) {
    try {
      await request(keyUrl(key), { method: 'DELETE' })
      if (selected?.key === key) setSelected(null)
      setError(null)
    } catch (err) {
      setError(err.message)
    }
    reload()
  }

  return (
    <div>
      {error && <p role="alert">Error: {error}</p>}
      <form onSubmit={handleSave}>
        <input placeholder="Key" value={newKey} onChange={e => setNewKey(e.target.value)} />
        <input placeholder="Value" value={newValue} onChange={e => setNewValue(e.target.value)} />
        <button type="submit">Save</button>
      </form>
      <ul>
        {keys.map(key => (
          <li key={key}>
            <button type="button" onClick={() => show(key)}>
              {key}
            </button>
            <button type="button" onClick={() => remove(key)}>
              Delete
            </button>
          </li>
        ))}
      </ul>
      {selected && (
        <div>
          <h3>{selected.key}</h3>
          <pre>{selected.value}</pre>
        </div>
      )}
    </div>
  )
}
