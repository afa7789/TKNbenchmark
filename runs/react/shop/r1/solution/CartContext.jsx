import { createContext, useContext, useMemo, useReducer } from "react";

const CartContext = createContext(null);

function cartReducer(items, action) {
  switch (action.type) {
    case "add": {
      const existing = items.find((item) => item.id === action.product.id);
      if (existing) {
        return items.map((item) =>
          item.id === action.product.id ? { ...item, quantity: item.quantity + 1 } : item
        );
      }
      return [...items, { ...action.product, quantity: 1 }];
    }
    case "remove":
      return items.filter((item) => item.id !== action.id);
    case "setQuantity": {
      const quantity = Math.max(0, Math.floor(Number(action.quantity) || 0));
      if (quantity === 0) return items.filter((item) => item.id !== action.id);
      return items.map((item) => (item.id === action.id ? { ...item, quantity } : item));
    }
    case "clear":
      return [];
    default:
      throw new Error(`Unknown action: ${action.type}`);
  }
}

export function CartProvider({ children }) {
  const [items, dispatch] = useReducer(cartReducer, []);

  const value = useMemo(
    () => ({
      items,
      count: items.reduce((sum, item) => sum + item.quantity, 0),
      add: (product) => dispatch({ type: "add", product }),
      remove: (id) => dispatch({ type: "remove", id }),
      setQuantity: (id, quantity) => dispatch({ type: "setQuantity", id, quantity }),
      clear: () => dispatch({ type: "clear" }),
    }),
    [items]
  );

  return <CartContext value={value}>{children}</CartContext>;
}

export function useCart() {
  const context = useContext(CartContext);
  if (!context) throw new Error("useCart must be used within a CartProvider");
  return context;
}
