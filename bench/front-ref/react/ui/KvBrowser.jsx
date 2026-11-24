import { useEffect, useState } from 'react'
export default function KvBrowser({ baseUrl }) {
  const [keys, setKeys] = useState([])
  const [error, setError] = useState(null)
  const load = () => fetch(`${baseUrl}/kv`).then((r) => r.json()).then(setKeys, setError)
  useEffect(() => { load() }, [baseUrl])
  return <div>{error && <p>{String(error)}</p>}<ul>{keys.map((k) => <li key={k}>{k}<button onClick={() => fetch(`${baseUrl}/kv/${k}`, { method: 'DELETE' }).then(load)}>Delete</button></li>)}</ul></div>
}
