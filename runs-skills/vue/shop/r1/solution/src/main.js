import { createApp } from 'vue'
import { createPinia } from 'pinia'
import App from './App.vue'

export function mountShop(el, products) {
  const app = createApp(App, { products })
  app.use(createPinia())
  app.mount(el)
  return app
}
