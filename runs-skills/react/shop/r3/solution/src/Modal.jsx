import { useEffect, useEffectEvent } from 'react'

export default function Modal({ onClose, children }) {
  const handleKeyDown = useEffectEvent((event) => {
    if (event.key === 'Escape') onClose()
  })

  useEffect(() => {
    document.addEventListener('keydown', handleKeyDown)
    return () => document.removeEventListener('keydown', handleKeyDown)
  }, [])

  return (
    <div role="dialog" aria-modal="true">
      <button type="button" aria-label="Close" onClick={onClose}>
        Close
      </button>
      {children}
    </div>
  )
}
