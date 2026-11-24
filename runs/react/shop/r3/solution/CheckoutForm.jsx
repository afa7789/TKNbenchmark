import { useState } from "react";
import { useCart } from "./CartContext.jsx";

function validate({ name, email }) {
  const errors = {};
  if (!name.trim()) errors.name = "Name is required";
  if (!email.includes("@")) errors.email = "Email must contain @";
  return errors;
}

export default function CheckoutForm({ onSubmitted }) {
  const { clear } = useCart();
  const [name, setName] = useState("");
  const [email, setEmail] = useState("");

  const errors = validate({ name, email });
  const isValid = Object.keys(errors).length === 0;

  function handleSubmit(event) {
    event.preventDefault();
    if (!isValid) return;
    clear();
    onSubmitted();
  }

  return (
    <form onSubmit={handleSubmit} noValidate>
      <label>
        Name
        <input value={name} onChange={(event) => setName(event.target.value)} />
      </label>
      {errors.name && <p role="alert">{errors.name}</p>}
      <label>
        Email
        <input type="email" value={email} onChange={(event) => setEmail(event.target.value)} />
      </label>
      {errors.email && <p role="alert">{errors.email}</p>}
      <button type="submit" disabled={!isValid}>
        Place order
      </button>
    </form>
  );
}
