import { useEffect, useRef, useState } from 'react'

export default function SearchBox({ onSearch, delay = 300 }) {
  const [text, setText] = useState('')
  const timerRef = useRef(null)

  useEffect(() => () => clearTimeout(timerRef.current), [])

  function handleChange(event) {
    const value = event.target.value
    setText(value)
    clearTimeout(timerRef.current)
    timerRef.current = setTimeout(() => onSearch(value), delay)
  }

  return (
    <input
      type="search"
      placeholder="Search products"
      aria-label="Search products"
      value={text}
      onChange={handleChange}
    />
  )
}
