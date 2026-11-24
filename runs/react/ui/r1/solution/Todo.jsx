import { useState } from "react";

export default function Todo() {
  const [text, setText] = useState("");
  const [items, setItems] = useState([]);

  function handleSubmit(e) {
    e.preventDefault();
    const value = text.trim();
    if (!value) return;
    setItems((prev) => [...prev, { id: crypto.randomUUID(), text: value }]);
    setText("");
  }

  function remove(id) {
    setItems((prev) => prev.filter((item) => item.id !== id));
  }

  return (
    <div>
      <form onSubmit={handleSubmit}>
        <input value={text} onChange={(e) => setText(e.target.value)} />
        <button type="submit">Add</button>
      </form>
      <ul>
        {items.map((item) => (
          <li key={item.id}>
            {item.text}
            <button type="button" onClick={() => remove(item.id)}>
              Remove
            </button>
          </li>
        ))}
      </ul>
    </div>
  );
}
