import { useState } from 'react'
import { CurrencyContext } from './CurrencyContext.js'
import CartProvider from './CartProvider.jsx'
import Header from './Header.jsx'
import ProductList from './ProductList.jsx'
import Cart from './Cart.jsx'
import Modal from './Modal.jsx'
import CheckoutForm from './CheckoutForm.jsx'

export default function App({ products = [] }) {
  const [isCheckoutOpen, setIsCheckoutOpen] = useState(false)

  const openCheckout = () => setIsCheckoutOpen(true)
  const closeCheckout = () => setIsCheckoutOpen(false)

  return (
    <CurrencyContext value="USD">
      <CartProvider>
        <Header onCheckout={openCheckout} />
        <ProductList products={products} />
        <Cart />
        {isCheckoutOpen && (
          <Modal onClose={closeCheckout}>
            <CheckoutForm onSubmitted={closeCheckout} />
          </Modal>
        )}
      </CartProvider>
    </CurrencyContext>
  )
}
