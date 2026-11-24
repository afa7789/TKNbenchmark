import { useState } from 'react'
export default function Counter() {
  const [n, setN] = useState(0)
  return <div><span>{n}</span><button onClick={() => setN(n + 1)}>Increment</button></div>
}
