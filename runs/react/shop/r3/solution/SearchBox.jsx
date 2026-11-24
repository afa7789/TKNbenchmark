import { useEffect, useRef, useState } from "react";

export default function SearchBox({ onSearch, delay = 300 }) {
  const [value, setValue] = useState("");
  const onSearchRef = useRef(onSearch);

  useEffect(() => {
    onSearchRef.current = onSearch;
  }, [onSearch]);

  useEffect(() => {
    const timer = setTimeout(() => onSearchRef.current(value), delay);
    return () => clearTimeout(timer);
  }, [value, delay]);

  return (
    <input
      type="search"
      placeholder="Search products"
      value={value}
      onChange={(event) => setValue(event.target.value)}
    />
  );
}
