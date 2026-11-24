import { useEffect, useState } from 'react'
export default function FetchUsers() {
  const [state, setState] = useState({ loading: true })
  useEffect(() => {
    fetch('https://jsonplaceholder.typicode.com/users').then((r) => r.json()).then((users) => setState({ users }), (error) => setState({ error }))
  }, [])
  if (state.loading) return <p>Loading…</p>
  if (state.error) return <p>Error: {state.error.message}</p>
  return <ul>{state.users.map((u) => <li key={u.id}>{u.name}</li>)}</ul>
}
