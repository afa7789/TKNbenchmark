import { useReducer } from 'react'
import { CartContext, cartReducer } from './CartContext.js'

export default function CartProvider({ children }) {
  const [items, dispatch] = useReducer(cartReducer, [])

  const cart = {
    items,
    count: items.reduce((sum, item) => sum + item.quantity, 0),
    add: product => dispatch({ type: 'add', product }),
    remove: id => dispatch({ type: 'remove', id }),
    setQuantity: (id, quantity) => dispatch({ type: 'setQuantity', id, quantity }),
    clear: () => dispatch({ type: 'clear' }),
  }

  return <CartContext value={cart}>{children}</CartContext>
}
