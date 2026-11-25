import { useMemo, useReducer } from 'react'
import { CartContext, cartReducer } from './CartContext.js'

export default function CartProvider({ children }) {
  const [items, dispatch] = useReducer(cartReducer, [])

  const actions = useMemo(
    () => ({
      add: (product) => dispatch({ type: 'add', product }),
      remove: (id) => dispatch({ type: 'remove', id }),
      setQuantity: (id, quantity) => dispatch({ type: 'setQuantity', id, quantity }),
      clear: () => dispatch({ type: 'clear' }),
    }),
    []
  )

  const value = useMemo(() => ({ items, ...actions }), [items, actions])

  return <CartContext value={value}>{children}</CartContext>
}
