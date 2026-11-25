---
name: vue
description: "Version-correct, idiomatic Vue for the installed toolchain (vue 3.5.46, vite 8.3.8, @vitejs/plugin-vue 6.0.11, pinia 4.1.0): API, build commands, idioms and pitfalls. Use whenever writing, building, testing or fixing Vue code."
---

# Vue 3.5 SFC + Vite 8 + Pinia 4 + Router 5

Stack: vue 3.5 (3.6/Vapor is RC only, don't use it), vite 8 (Rolldown+Oxc), @vitejs/plugin-vue 6, pinia 4, vue-router 5, vitest 4/5, vue-tsc 3. Node `^20.19 || >=22.12`. Default: `<script setup lang="ts">`.

## Setup and commands
```sh
npm create vue@latest app -- --ts --router --pinia --vitest --eslint  # --bare: no demo
npm run build                  # vue-tsc --build + vite build
npx vitest run
npx vue-tsc --build --force    # --build is incremental, can miss changes
```
- Keep `typescript ~6.0`. vue-tsc 3 crashes on TS 7 (`ERR_PACKAGE_PATH_NOT_EXPORTED './lib/tsc'`). Vite only strips types, so only vue-tsc reports type errors.
- Layout: `src/{main.ts,App.vue,components,views|pages,stores,router,composables,assets}`, tests in `src/**/__tests__/*.spec.ts`, `env.d.ts` (`/// <reference types="vite/client" />`), alias `@`→`src`.
- Pinia 4 is ESM-only and has peer `@vue/devtools-api@^8`.

## `<script setup>` (verified 3.5.46)
```vue
<script setup lang="ts" generic="T extends { id: number; label: string }">
import { computed, useTemplateRef, useId } from 'vue'
const { items, max = 10 } = defineProps<{ items: T[]; max?: number }>() // reactive destructure + defaults
const emit = defineEmits<{ select: [item: T] }>()
const filter = defineModel<string>('filter', { default: '' })            // v-model:filter
const [count, mods] = defineModel<number, 'double'>('count', {
  default: 0, set: (v) => (mods.double ? v * 2 : v),                     // v-model:count.double
})
defineSlots<{ default(p: { item: T }): any }>()
defineOptions({ inheritAttrs: false })
const input = useTemplateRef<HTMLInputElement>('input')
const id = useId()                                                       // SSR-stable
const visible = computed(() => items.filter((i) => i.label.includes(filter.value)).slice(0, max))
defineExpose({ focus: () => input.value?.focus() })
</script>
<template>
  <input :id ref="input" v-model.trim="filter" v-bind="$attrs" @keyup.enter="count++" />
  <li v-for="item in visible" :key="item.id" @click="emit('select', item)">
    <slot :item>{{ item.label }}</slot>
  </li>
</template>
```
- Destructured props compile to `props.x`. Pass them as getters: `watch(() => x, …)`, `useFoo(() => x)`. Passing one directly or assigning to it is a compile error. Don't combine destructuring with `withDefaults`.
- Macros are hoisted, so `defineProps` can't reference local refs. Types used in macros must be resolvable `import type` paths.
- `useTemplateRef` inside `v-for` gives an array. Component refs are inferred by vue-tsc. For explicit types use `InstanceType<typeof C>`, or `ComponentExposed<typeof C>` (`vue-component-type-helpers`) for generic components.
- `model.value.prop = x` on an object model mutates the parent's object **without emitting**. Assign a new object instead.
- `:id` is shorthand for `:id="id"`. `<Teleport defer to="#el">` can target an element rendered later. The prop is `to`.

## Reactivity
- Use `shallowRef` for big or immutable data (replace `.value`, or call `triggerRef`) and `markRaw` for 3rd-party instances.
- Don't destructure `reactive()` or a store: use `toRefs` / `storeToRefs`. Write `watch(() => s.n, cb)`, not `watch(s.n, cb)`.
- watch options: `deep: 2` (depth), `once: true`. Handle: `h.pause()`, `h.resume()`, `h()` stops it.
- `onWatcherCleanup(() => ctrl.abort())` must run **before any `await`**, otherwise you get "no active watcher" and it does nothing. After an await, use the callback's 3rd arg `onCleanup`.
- Derive with `computed`, not watchers that write refs. Composable inputs: `MaybeRefOrGetter<T>` + `toValue()`.

## Pinia 4 (API unchanged from v2/v3)
```ts
export const useUserStore = defineStore('user', () => {
  const name = ref('')
  const loggedIn = computed(() => !!name.value)
  async function login(n: string) { name.value = n }
  function $reset() { name.value = '' }    // setup stores have no built-in $reset
  return { name, loggedIn, login, $reset } // return ALL state (SSR/devtools)
})
if (import.meta.hot) import.meta.hot.accept(acceptHMRUpdate(useUserStore, import.meta.hot))
```
- Usage: `const s = useUserStore(); const { name } = storeToRefs(s); s.login('x')`. Batch updates with `s.$patch({...})`.
- In guards or modules, call `useXStore()` inside the function, after `app.use(pinia)`. Otherwise you get `"getActivePinia()" was called but there was no active Pinia`.

## Vue Router 5
- The v4 API is unchanged. Guards **return** `false`, a location, or nothing (`next()` is deprecated): `router.beforeEach((to) => { if (to.meta.auth && !ok()) return { name: 'login' } })`.
- The component is reused across param changes, so watch `() => route.params.id`. Untyped params are `string | string[]`.
- Built-in file routing (replaces unplugin-vue-router). Put `VueRouter` from `'vue-router/vite'` **before** `vue()`: `plugins: [VueRouter({ dts: 'src/route-map.d.ts' }), vue()]`. Then `import { routes, handleHotUpdate } from 'vue-router/auto-routes'` and add `if (import.meta.hot) handleHotUpdate(router)`. `src/pages/users/[id].vue` becomes name `'/users/[id]'`. `useRoute('/users/[id]').params.id` is a typed `string`, and `definePage({ meta })` is a global macro. Commit `route-map.d.ts`.

## Vite 8 config
```ts
export default defineConfig({
  plugins: [vue({ features: { optionsAPI: false } })],   // drop Options API if unused
  resolve: { alias: { '@': fileURLToPath(new URL('./src', import.meta.url)) } },
  server: { proxy: { '/api': { target: 'http://localhost:3000', changeOrigin: true } } },
  build: { rolldownOptions: { output: { codeSplitting: { groups: [{ name: 'vendor', test: /node_modules/ }] } } } },
})
```
- `rollupOptions` → `rolldownOptions`. Object `manualChunks` is removed (use `codeSplitting`). `esbuild` option → `oxc`. Minifiers are Oxc (JS) and Lightning CSS. esbuild isn't installed.
- Only `VITE_*` env vars reach `import.meta.env`. Type them via `interface ImportMetaEnv { readonly VITE_X: string }` in `env.d.ts`.

## Testing
```ts
const w = mount(Comp, {
  props: { modelValue: 'a', 'onUpdate:modelValue': (v: string) => w.setProps({ modelValue: v }) },
  global: { plugins: [createTestingPinia({ createSpy: vi.fn, initialState: { user: { name: 'x' } } })] },
})
await w.find('input').setValue('b')          // await every trigger/setValue
expect(w.emitted('select')?.[0]).toEqual([item]); await flushPromises()
```
- `createTestingPinia` needs `createSpy: vi.fn` unless `globals: true`. Otherwise it throws `PINIA_TESTING_C0001`. Actions are stubbed (`stubActions: false` runs them). For plain store tests: `beforeEach(() => setActivePinia(createPinia()))`.
- Config: `mergeConfig(viteConfig, defineConfig({ test: { environment: 'jsdom' } }))`. Vitest 5: `vi.mock` only at top level (otherwise it errors), `clearMocks` defaults to true, and `.resolves`/`.rejects` must be awaited.

## Errors → fix
- `"x" is a destructured prop and should not be passed directly to watch()` → use `() => x`.
- `defineProps() … cannot reference locally declared variables` → move the value to module scope or an import.
- `Failed to resolve component: X` → import it. For web components: `vue({ template: { compilerOptions: { isCustomElement: (t) => t.includes('-') } } })`.
- `runtime compilation is not supported in this build` → use an SFC, or alias `vue` → `vue/dist/vue.esm-bundler.js`.
- `Set operation on key "x" failed: target is readonly` → you mutated a prop. Emit or use `defineModel`.
- `Extraneous non-props attributes … fragment` → `inheritAttrs: false` + `v-bind="$attrs"`.
- `inject() can only be used inside setup()` / `… no active component instance` → call composables and hooks synchronously in setup, before any `await`.
- Hydration mismatch → `useId()`, client-only values in `onMounted`, `data-allow-mismatch="text"`. Lazy hydration: `defineAsyncComponent({ loader, hydrate: hydrateOnVisible() })`. SSR uses `createSSRApp` + `renderToString` from `vue/server-renderer`.
