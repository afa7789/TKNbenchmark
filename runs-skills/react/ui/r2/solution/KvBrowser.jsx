import { useEffect, useState } from 'react'

async function request(url, options) {
  const res = await fetch(url, options)
  if (!res.ok) throw new Error(`${res.status} ${res.statusText}`)
  return res
}

export default function KvBrowser({ baseUrl }) {
  const [keys, setKeys] = useState([])
  const [version, setVersion] = useState(0)
  const [selected, setSelected] = useState(null)
  const [value, setValue] = useState('')
  const [newKey, setNewKey] = useState('')
  const [newValue, setNewValue] = useState('')
  const [error, setError] = useState(null)

  const keyUrl = key => `${baseUrl}/kv/${encodeURIComponent(key)}`

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

  const reload = () => setVersion(v => v + 1)

  async function show(key) {
    setError(null)
    try {
      const res = await request(keyUrl(key))
      setSelected(key)
      setValue(await res.text())
    } catch (err) {
      setError(err.message)
    }
  }

  async function save(e) {
    e.preventDefault()
    const key = newKey.trim()
    if (!key) return
    setError(null)
    try {
      await request(keyUrl(key), { method: 'PUT', body: newValue })
      if (key === selected) setValue(newValue)
      setNewKey('')
      setNewValue('')
    } catch (err) {
      setError(err.message)
    }
    reload()
  }

  async function remove(key) {
    setError(null)
    try {
      await request(keyUrl(key), { method: 'DELETE' })
      if (key === selected) {
        setSelected(null)
        setValue('')
      }
    } catch (err) {
      setError(err.message)
    }
    reload()
  }

  return (
    <div>
      {error && <p role="alert">Error: {error}</p>}
      <form onSubmit={save}>
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
      {selected !== null && (
        <section>
          <h2>{selected}</h2>
          <pre>{value}</pre>
        </section>
      )}
    </div>
  )
}
