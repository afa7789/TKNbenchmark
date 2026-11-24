import { useCallback, useState } from "react";
import { CurrencyContext } from "./CurrencyContext.jsx";
import { CartProvider } from "./CartContext.jsx";
import Header from "./Header.jsx";
import ProductList from "./ProductList.jsx";
import Cart from "./Cart.jsx";
import Modal from "./Modal.jsx";
import CheckoutForm from "./CheckoutForm.jsx";

export default function App({ products }) {
  const [checkoutOpen, setCheckoutOpen] = useState(false);
  const openCheckout = useCallback(() => setCheckoutOpen(true), []);
  const closeCheckout = useCallback(() => setCheckoutOpen(false), []);

  return (
    <CurrencyContext value="USD">
      <CartProvider>
        <Header onCheckout={openCheckout} />
        <ProductList products={products} />
        <Cart />
        {checkoutOpen && (
          <Modal title="Checkout" onClose={closeCheckout}>
            <CheckoutForm onComplete={closeCheckout} />
          </Modal>
        )}
      </CartProvider>
    </CurrencyContext>
  );
}
