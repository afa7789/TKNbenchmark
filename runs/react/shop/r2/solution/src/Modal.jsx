import { useEffect } from "react";

export default function Modal({ onClose, children }) {
  useEffect(() => {
    function handleKeyDown(event) {
      if (event.key === "Escape") {
        onClose();
      }
    }
    document.addEventListener("keydown", handleKeyDown);
    return () => document.removeEventListener("keydown", handleKeyDown);
  }, [onClose]);

  return (
    <div role="dialog" aria-modal="true">
      <button type="button" aria-label="Close" onClick={onClose}>
        ×
      </button>
      {children}
    </div>
  );
}
