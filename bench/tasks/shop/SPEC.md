# shop — a small shopping app

Build a small shopping app as several components, structured the way an experienced developer of
the framework you were given would structure it. Plain JavaScript (no TypeScript), no styling, no
comments, no build setup, no `package.json`, no tests. One component per file, named after the
component; shared state goes in its own file.

`App` receives a `products` prop: an array of `{ id, name, price, category }`.

Every interaction below is required:

1. **App** — the root. Makes the shop's currency (`"USD"`) available to every descendant without
   passing it through props (context / provide–inject). Renders `Header`, `ProductList`, `Cart`, and
   a `Modal` containing `CheckoutForm`.
2. **Cart state** — global state shared by `Header`, `ProductList` and `Cart`: items with
   quantities and the actions add, remove, set quantity and clear. Use the global-state approach an
   experienced developer of this framework would pick.
3. **Header** — shows how many items are in the cart and a button that opens the checkout modal.
4. **SearchBox** — a child of `ProductList`. A text input that reports the query to its parent only
   after the user has stopped typing for 300 ms. A pending timer is cancelled when it unmounts.
5. **ProductList** — filters the products by the search query and by a category `<select>`,
   renders one `ProductItem` per product as a keyed list, and shows `No products` when nothing
   matches.
6. **ProductItem** — receives one product as a prop. Its "Add" button tells the parent through an
   event / callback; the parent adds the product to the cart.
7. **Cart** — lists the cart items, each with a two-way-bound quantity input and a remove button.
   Shows subtotal, 10% tax and total as derived values, formatted with the currency from step 1.
8. **Modal** — a generic dialog that renders whatever content its parent passes in (children /
   slot / snippet). Closes on Escape or a close button, and removes its key listener on unmount.
9. **CheckoutForm** — name and email inputs bound to local state. Validation: name required, email
   must contain `@`; each field shows its own error; submit is disabled while invalid. Submitting
   clears the cart and closes the modal.
