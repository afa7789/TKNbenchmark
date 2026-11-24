import { useState } from 'react'
export default function Todo() {
  const [text, setText] = useState('')
  const [items, setItems] = useState([])
  const add = () => text.trim() && (setItems([...items, { id: Date.now(), text }]), setText(''))
  return (
    <div>
      <input value={text} onChange={(e) => setText(e.target.value)} />
      <button onClick={add}>Add</button>
      <ul>{items.map((i) => <li key={i.id}>{i.text}<button onClick={() => setItems(items.filter((x) => x !== i))}>Remove</button></li>)}</ul>
    </div>
  )
}
