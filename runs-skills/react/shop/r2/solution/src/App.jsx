import { useState } from 'react'
import { CurrencyContext } from './CurrencyContext.js'
import CartProvider from './CartProvider.jsx'
import Header from './Header.jsx'
import ProductList from './ProductList.jsx'
import Cart from './Cart.jsx'
import Modal from './Modal.jsx'
import CheckoutForm from './CheckoutForm.jsx'

export default function App({ products = [] }) {
  const [checkoutOpen, setCheckoutOpen] = useState(false)
  const closeCheckout = () => setCheckoutOpen(false)

  return (
    <CurrencyContext value="USD">
      <CartProvider>
        <Header onCheckout={() => setCheckoutOpen(true)} />
        <main>
          <ProductList products={products} />
          <Cart />
        </main>
        {checkoutOpen && (
          <Modal title="Checkout" onClose={closeCheckout}>
            <CheckoutForm onSubmitted={closeCheckout} />
          </Modal>
        )}
      </CartProvider>
    </CurrencyContext>
  )
}
