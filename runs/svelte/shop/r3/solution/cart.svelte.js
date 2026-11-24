class CartStore {
  items = $state([]);
  count = $derived(this.items.reduce((sum, item) => sum + item.quantity, 0));
  subtotal = $derived(this.items.reduce((sum, item) => sum + item.price * item.quantity, 0));

  add(product) {
    const existing = this.items.find((item) => item.id === product.id);
    if (existing) {
      existing.quantity += 1;
    } else {
      this.items.push({ id: product.id, name: product.name, price: product.price, quantity: 1 });
    }
  }

  remove(id) {
    this.items = this.items.filter((item) => item.id !== id);
  }

  setQuantity(id, quantity) {
    const item = this.items.find((item) => item.id === id);
    if (item) {
      item.quantity = Math.max(1, Math.floor(Number(quantity)) || 1);
    }
  }

  clear() {
    this.items = [];
  }
}

export const cart = new CartStore();
