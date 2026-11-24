# ui — six front-end components

Write each component as one idiomatic file, the way an experienced developer of the framework you
were given would write it. Plain JavaScript (no TypeScript), no styling, no comments, no build
setup, no `package.json`, no tests. Name each file after the component (`Hello.jsx` / `Hello.vue`…).

1. **Hello** — renders `Hello, <name>!` from a `name` prop.
2. **Counter** — shows a count that starts at 0 and a button that increments it.
3. **Todo** — a text input and an "Add" button append items to a list; each item has a "Remove"
   button. Empty input adds nothing.
4. **FetchUsers** — on mount fetches `https://jsonplaceholder.typicode.com/users`; shows
   `Loading…`, then a list of user names, or `Error: <message>` if the request fails.
5. **FilterTable** — takes a `rows` prop of `{ name, price, qty }`. A search box filters rows by
   name (case-insensitive). Clicking a column header sorts by it; clicking again flips the order.
   A footer shows the total of `price * qty` over the visible rows.
6. **KvBrowser** — a client for the kvhttp API at a `baseUrl` prop:
   `GET /kv` returns a JSON array of keys, `GET /kv/<key>` returns the value as text,
   `PUT /kv/<key>` stores the request body, `DELETE /kv/<key>` deletes. It lists the keys;
   clicking a key shows its value; a form with key and value inputs saves an entry; each key has a
   delete button. The list reloads after every change, and request errors are shown.
