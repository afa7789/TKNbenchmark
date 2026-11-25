import { formatMoney, useCurrency } from './CurrencyContext.js'

export default function ProductItem({ product, onAdd }) {
  const currency = useCurrency()

  return (
    <li>
      <span>{product.name}</span> <span>{formatMoney(product.price, currency)}</span>{' '}
      <button type="button" onClick={() => onAdd(product)}>Add</button>
    </li>
  )
}
