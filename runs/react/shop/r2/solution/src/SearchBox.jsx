import { useEffect, useState } from "react";

export default function SearchBox({ onSearch }) {
  const [value, setValue] = useState("");

  useEffect(() => {
    const timer = setTimeout(() => onSearch(value), 300);
    return () => clearTimeout(timer);
  }, [value, onSearch]);

  return (
    <input
      type="search"
      placeholder="Search products"
      aria-label="Search products"
      value={value}
      onChange={(event) => setValue(event.target.value)}
    />
  );
}
