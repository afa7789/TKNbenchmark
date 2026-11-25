import { createContext, use } from 'react'

export const CartContext = createContext(null)

export function cartReducer(items, action) {
  switch (action.type) {
    case 'add': {
      const existing = items.find((item) => item.id === action.product.id)
      if (existing) {
        return items.map((item) =>
          item.id === action.product.id ? { ...item, quantity: item.quantity + 1 } : item
        )
      }
      return [...items, { ...action.product, quantity: 1 }]
    }
    case 'remove':
      return items.filter((item) => item.id !== action.id)
    case 'setQuantity':
      return items.map((item) =>
        item.id === action.id ? { ...item, quantity: action.quantity } : item
      )
    case 'clear':
      return []
    default:
      throw new Error(`Unknown cart action: ${action.type}`)
  }
}

export function useCart() {
  const cart = use(CartContext)
  if (!cart) throw new Error('useCart must be used within a CartProvider')
  return cart
}
