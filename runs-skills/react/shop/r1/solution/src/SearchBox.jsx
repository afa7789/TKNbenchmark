import { useEffect, useRef, useState } from 'react'

export default function SearchBox({ onSearch, delay = 300 }) {
  const [value, setValue] = useState('')
  const timerRef = useRef(null)

  useEffect(() => () => clearTimeout(timerRef.current), [])

  function handleChange(e) {
    const next = e.target.value
    setValue(next)
    clearTimeout(timerRef.current)
    timerRef.current = setTimeout(() => onSearch(next), delay)
  }

  return (
    <input
      type="search"
      placeholder="Search products"
      aria-label="Search products"
      value={value}
      onChange={handleChange}
    />
  )
}
