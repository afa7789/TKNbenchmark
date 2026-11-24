class CartStore {
  items = $state([]);
  count = $derived(this.items.reduce((sum, item) => sum + item.quantity, 0));
  subtotal = $derived(this.items.reduce((sum, item) => sum + item.price * item.quantity, 0));

  add(product) {
    const item = this.items.find((i) => i.id === product.id);
    if (item) item.quantity += 1;
    else this.items.push({ ...product, quantity: 1 });
  }

  remove(id) {
    this.items = this.items.filter((i) => i.id !== id);
  }

  setQuantity(id, quantity) {
    if (!Number.isFinite(quantity)) return;
    if (quantity <= 0) return this.remove(id);
    const item = this.items.find((i) => i.id === id);
    if (item) item.quantity = Math.floor(quantity);
  }

  clear() {
    this.items = [];
  }
}

export const cart = new CartStore();
