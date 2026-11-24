import { useState } from "react";
import { CurrencyContext } from "./CurrencyContext.jsx";
import { CartProvider } from "./CartContext.jsx";
import Header from "./Header.jsx";
import ProductList from "./ProductList.jsx";
import Cart from "./Cart.jsx";
import Modal from "./Modal.jsx";
import CheckoutForm from "./CheckoutForm.jsx";

export default function App({ products }) {
  const [isCheckoutOpen, setIsCheckoutOpen] = useState(false);
  const closeCheckout = () => setIsCheckoutOpen(false);

  return (
    <CurrencyContext value="USD">
      <CartProvider>
        <Header onCheckout={() => setIsCheckoutOpen(true)} />
        <ProductList products={products} />
        <Cart />
        {isCheckoutOpen && (
          <Modal onClose={closeCheckout}>
            <CheckoutForm onSubmitted={closeCheckout} />
          </Modal>
        )}
      </CartProvider>
    </CurrencyContext>
  );
}
