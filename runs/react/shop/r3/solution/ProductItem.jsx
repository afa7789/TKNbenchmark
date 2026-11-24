import { useFormatPrice } from "./CurrencyContext.jsx";

export default function ProductItem({ product, onAdd }) {
  const formatPrice = useFormatPrice();

  return (
    <li>
      <span>{product.name}</span> <span>{formatPrice(product.price)}</span>{" "}
      <button type="button" onClick={() => onAdd(product)}>
        Add
      </button>
    </li>
  );
}
