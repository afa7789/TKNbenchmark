import { useState } from 'react'
import { useCart } from './CartContext.js'

export default function CheckoutForm({ onComplete }) {
  const { clear } = useCart()
  const [name, setName] = useState('')
  const [email, setEmail] = useState('')

  const nameError = name.trim() ? '' : 'Name is required'
  const emailError = email.includes('@') ? '' : 'Email must contain @'
  const isValid = !nameError && !emailError

  function handleSubmit(e) {
    e.preventDefault()
    if (!isValid) return
    clear()
    onComplete()
  }

  return (
    <form onSubmit={handleSubmit} noValidate>
      <label>
        Name
        <input value={name} onChange={e => setName(e.target.value)} />
      </label>
      {nameError && <p role="alert">{nameError}</p>}
      <label>
        Email
        <input type="email" value={email} onChange={e => setEmail(e.target.value)} />
      </label>
      {emailError && <p role="alert">{emailError}</p>}
      <button type="submit" disabled={!isValid}>Place order</button>
    </form>
  )
}
