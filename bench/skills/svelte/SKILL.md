---
name: svelte
description: "Version-correct, idiomatic Svelte for the installed toolchain (svelte 5.59.1, vite 8.3.8, @sveltejs/vite-plugin-svelte 7.3.2): API, build commands, idioms and pitfalls. Use whenever writing, building, testing or fixing Svelte code."
---

# Svelte 5 (5.59) — runes mode

Verified: svelte 5.59.1, vite 8, vite-plugin-svelte 7, svelte-check 4.7, TS 6. Runes mode only. Never use `export let`, `$:`, `on:click`, `<slot>`, `$$props`, `createEventDispatcher`, `<svelte:component>`, `<svelte:self>`, `class:`, `use:` or `{@const}`.

## Project and commands
```sh
npm create vite@latest app -- --template svelte-ts   # SPA; SvelteKit: npx sv create app
npx vite build; npx vite preview
npx svelte-check --tsconfig ./tsconfig.json  # types, a11y, warnings (CI)
npx vitest run
npx -y @sveltejs/mcp svelte-autofixer src/lib/X.svelte --svelte-version 5.59.1  # official linter; rerun until clean
```
- svelte-check refuses TypeScript 7 alone: pin `typescript@~6`.
- Runes only work in `.svelte`, `.svelte.ts`, `.svelte.js`. In plain `.ts`, `$state` passes build and svelte-check, then throws `$state is not defined`.
- Layout: `src/main.ts` calls `mount(App, { target })` (not `new App()`). Components in `src/lib/*.svelte`, logic in `src/lib/*.svelte.ts`, tests colocated.
```ts
// vite.config.ts (svelte-check reads these inline options too)
import { svelte } from '@sveltejs/vite-plugin-svelte';
import { defineConfig } from 'vitest/config';
export default defineConfig({
  plugins: [svelte({ compilerOptions: {
    runes: ({ filename }) => (filename.split(/[/\\]/).includes('node_modules') ? undefined : true), // force runes except deps
    experimental: { async: true } // only if using `await` in components
  } })],
  resolve: process.env.VITEST ? { conditions: ['browser'] } : undefined, // else mount() throws lifecycle_function_unavailable
  test: { environment: 'jsdom' }
});
```
`lang="ts"` needs no preprocessor, but enums fail (`typescript_invalid_feature`): use unions, or `preprocess: vitePreprocess({ script: true })`.

## Component skeleton
```svelte
<script lang="ts" generics="T extends { id: string }">
  import type { Snippet } from 'svelte';
  import type { HTMLButtonAttributes } from 'svelte/elements';
  interface Props extends HTMLButtonAttributes {
    items: T[]; value?: string; onpick?: (item: T) => void; // callback props, not events
    row: Snippet<[T, number]>; children?: Snippet;
  }
  let { items, value = $bindable(''), onpick, row, children, class: cls, ...rest }: Props = $props();
  const id = $props.id(); // SSR-stable
  let query = $state('');
  let shown = $derived(items.filter((i) => i.id.includes(query))); // expression; $derived.by(fn) for blocks
  export function clear() { query = ''; } // via bind:this
</script>

<input {id} bind:value={query} />
<button {...rest} class={['btn', cls, { active: !!query }]} onclick={() => onpick?.(items[0])}>
  {@render children?.()}
</button>
{#each shown as item, i (item.id)}{@render row(item, i)}{:else}<p>none</p>{/each}
```
- Destructured props stay reactive, but `let x = $state(prop)` or `const y = prop * 2` captures only the initial value (`state_referenced_locally`). Use `$derived(prop * 2)`. A `$derived` can be reassigned (optimistic UI); it recomputes when deps change. Never `$state` + `$effect` for this.
- `$state([])` or `$state({})` is a deep proxy (`push`, `obj.k = v` are reactive). `$state.raw` for big data you only replace. `$state.snapshot(x)` before `structuredClone`/`postMessage`/logging.
- Don't mutate unowned props (`ownership_invalid_mutation`): use a callback prop, or `$bindable()` in the child + `bind:prop` in the parent.

## Shared state (`x.svelte.ts`)
```ts
import { createContext } from 'svelte';
export class Cart {
  items = $state<{ id: string; qty: number }[]>([]);
  total = $derived(this.items.reduce((s, i) => s + i.qty, 0));
  add = (id: string) => { this.items.push({ id, qty: 1 }); }; // arrow keeps `this` for onclick={cart.add}
  toJSON() { return { items: this.items }; } // fields aren't enumerable: JSON.stringify → {}
}
export const [getCart, setCart, hasCart] = createContext<Cart>(); // call during component init
export const prefs = $state({ theme: 'light' }); // OK: only mutated, never reassigned
```
- A reassigned `export let n = $state(0)` fails (`state_invalid_export`), as does `export const d = $derived(...)` (`derived_invalid_export`). Export an object, class instance or getter function.
- `getCart()` with no ancestor `setCart()` throws `missing_context`. Under SSR prefer context: module state is shared across requests.
- `svelte/reactivity`: `SvelteMap` (has `getOrInsert`), `SvelteSet`, `SvelteDate`, `SvelteURL`, `MediaQuery` (`.current`), `createSubscriber`. `svelte/reactivity/window`: `innerWidth.current` etc. `svelte/motion`: `new Spring(v)`/`new Tween(v, opts)` with `.target`, `.current`.

## Template idioms
- Events are attributes: `onclick={fn}`, `{onclick}`, `onclickcapture`. No modifiers (`onsubmit|preventDefault` fails): call `e.preventDefault()`. Mixing `on:` and `on…` is an error. Use `<svelte:window onkeydown={…} />`/`<svelte:document>`, not `$effect` listeners. Imperative: `on(el, 'click', fn)` (`svelte/events`) returns an unsubscriber.
- `{@render snippet()}` must be a call. `children?.()` if optional. Content inside `<Comp>` is the `children` prop. `{#snippet name(a)}` inside `<Comp>` is prop `name`.
- Declaration tags (5.56+) replace `{@const}`: `{const area = w * h}`; `{let n = $state(0)}` = local state in a block.
- Attachments replace actions: `<div {@attach tooltip(text)}>` with `const tooltip = (t: string): Attachment<HTMLElement> => (node) => { …; return () => cleanup }`. Re-runs when state it reads changes. `fromAction` wraps old actions.
- Function binding: `bind:value={() => v, (n) => (v = clamp(n))}`. For `bind:this`, use `let el = $state<HTMLElement>()`.
- `animate:` only on the sole child of a keyed `{#each}`, not in a snippet (`animation_invalid_placement`). Duplicate keys throw `each_key_duplicate`; never key by index.
- Dynamic: `const C = $derived(cond ? A : B)`; `<C />`. CSS vars: `style:--accent={c}`, `<Child --accent="red" />`. Child styling: `.wrap :global { p {…} }`.
- `<div></div>` not `<div />`; `<script module>` not `context="module"`.

## Effects
Only for syncing DOM/canvas/third-party libs. Deps = values read synchronously (not after `await`/in timers); `untrack(() => x)` excludes one. Return a cleanup. Never run in SSR (no `if (browser)`). `$effect.pre` runs before DOM updates. Debug: `$inspect(x)`, `$inspect.trace()` (first statement).
- Writing state the effect reads → `effect_update_depth_exceeded`. Use `$derived` or a handler.
- Mutating state in `$derived`/markup (`$derived(arr.sort())`) → `state_unsafe_mutation`. Use `toSorted()`.

## Async (`experimental.async`)
```svelte
<script lang="ts">
  import { getAbortSignal } from 'svelte';
  let { id } = $props();
  const user = $derived(await fetch(`/u/${id}`, { signal: getAbortSignal() }).then((r) => r.json()));
</script>
<svelte:boundary>
  <p>{user.name} {await other(id)}</p>
  {#snippet pending()}<p>loading…</p>{/snippet}
  {#snippet failed(error, reset)}<button onclick={reset}>retry</button>{/snippet}
</svelte:boundary>
{#if $effect.pending()}<span>updating…</span>{/if}
```
- `getAbortSignal()` must precede the first `await` (5.58.1+). No flag → `experimental_async` error. `await settled()` waits for the update; `$state.eager(v)` shows a value immediately.
- SSR: `const { head, body } = await render(App, { props })` (`svelte/server`); `await hydratable('key', () => load())` stops hydration refetching.

## Testing (Vitest + jsdom)
```ts
// x.svelte.test.ts — `.svelte` in the name enables runes
const cleanup = $effect.root(() => { let n = $state(0); $effect(() => log.push(n)); flushSync(); n = 1; flushSync(); });
cleanup(); // effects in tests need $effect.root; flushSync() runs them now
const cmp = mount(Field, { target: document.body, props: { label: 'L' } });
btn.click(); flushSync(); expect(document.body.textContent).toContain('1'); unmount(cmp);
```
`@testing-library/svelte` (`render(Comp, props)`, `screen`) also works; wrap snippet/binding/context cases in a test component.
