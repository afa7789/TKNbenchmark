import { useEffect, useState } from 'react'

export default function FetchUsers() {
  const [users, setUsers] = useState(null)
  const [error, setError] = useState(null)

  useEffect(() => {
    const controller = new AbortController()

    fetch('https://jsonplaceholder.typicode.com/users', { signal: controller.signal })
      .then(res => {
        if (!res.ok) throw new Error(`HTTP ${res.status}`)
        return res.json()
      })
      .then(setUsers)
      .catch(err => {
        if (err.name !== 'AbortError') setError(err)
      })

    return () => controller.abort()
  }, [])

  if (error) return <p>Error: {error.message}</p>
  if (!users) return <p>Loading…</p>

  return (
    <ul>
      {users.map(user => (
        <li key={user.id}>{user.name}</li>
      ))}
    </ul>
  )
}
