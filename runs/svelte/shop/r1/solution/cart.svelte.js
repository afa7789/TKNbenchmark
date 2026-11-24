class CartStore {
  items = $state([]);

  count = $derived(this.items.reduce((sum, item) => sum + item.quantity, 0));

  add(product) {
    const existing = this.items.find((item) => item.id === product.id);
    if (existing) {
      existing.quantity += 1;
    } else {
      this.items.push({ ...product, quantity: 1 });
    }
  }

  remove(id) {
    this.items = this.items.filter((item) => item.id !== id);
  }

  setQuantity(id, quantity) {
    const qty = Math.floor(Number(quantity));
    if (!Number.isFinite(qty) || qty <= 0) {
      this.remove(id);
      return;
    }
    const item = this.items.find((item) => item.id === id);
    if (item) item.quantity = qty;
  }

  clear() {
    this.items = [];
  }
}

export const cart = new CartStore();
