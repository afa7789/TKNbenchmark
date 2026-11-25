import { useEffect, useEffectEvent } from 'react'

export default function Modal({ title, onClose, children }) {
  const handleKeyDown = useEffectEvent((event) => {
    if (event.key === 'Escape') onClose()
  })

  useEffect(() => {
    const listener = (event) => handleKeyDown(event)
    window.addEventListener('keydown', listener)
    return () => window.removeEventListener('keydown', listener)
  }, [])

  return (
    <div role="dialog" aria-modal="true" aria-label={title}>
      {title && <h2>{title}</h2>}
      <button type="button" aria-label="Close" onClick={onClose}>
        Close
      </button>
      {children}
    </div>
  )
}
