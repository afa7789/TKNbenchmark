import { useEffect, useEffectEvent } from 'react'

export default function Modal({ title, onClose, children }) {
  const handleKeyDown = useEffectEvent(e => {
    if (e.key === 'Escape') onClose()
  })

  useEffect(() => {
    const listener = e => handleKeyDown(e)
    document.addEventListener('keydown', listener)
    return () => document.removeEventListener('keydown', listener)
  }, [])

  return (
    <div role="dialog" aria-modal="true" aria-label={title}>
      {title && <h2>{title}</h2>}
      <button type="button" aria-label="Close" onClick={onClose}>Close</button>
      {children}
    </div>
  )
}
