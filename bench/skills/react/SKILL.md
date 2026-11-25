---
name: react
description: "Version-correct, idiomatic React for the installed toolchain (react 19.3.1, react-dom 19.3.1, vite 8.3.8, @vitejs/plugin-react 6.3.0): API, build commands, idioms and pitfalls. Use whenever writing, building, testing or fixing React code."
---

# React 19.3 + Vite 8 (function components, `.jsx`)

Verified on react 19.3.1, vite 8.3.8, plugin-react 6.3.0, vitest 5.

## Project setup and commands
```sh
npm create vite@latest my-app -- --template react   # Node ^20.19 || >=22.12
npm run dev | npm run build (-> dist/) | npm run preview
npm i -D vitest jsdom @testing-library/react @testing-library/jest-dom @testing-library/user-event
```
- `package.json` needs `"type": "module"`.
- **JSX only in `.jsx` files.** JSX in a `.js` file fails with `Unexpected JSX expression … JSX syntax is disabled`.
- Layout: `index.html` (root, loads `/src/main.jsx`), `src/main.jsx`, `src/App.jsx`, `src/components/*.jsx`. Put hooks and contexts in their own files: a component file must export only components, or Fast Refresh breaks.
- Vite 8: `build.rolldownOptions` (`rollupOptions` deprecated), `oxc` replaces `esbuild`.

```js
// src/main.jsx
import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import App from './App.jsx'
createRoot(document.getElementById('root'), {
  onUncaughtError: (error, info) => report(error, info.componentStack),
  onCaughtError: (error) => report(error),   // caught by boundaries
}).render(<StrictMode><App /></StrictMode>)
```

```js
// vite.config.js (Vitest reads the `test` key)
import react from '@vitejs/plugin-react'
import { defineConfig } from 'vite'
export default defineConfig({
  plugins: [react()],
  test: { environment: 'jsdom', globals: true, setupFiles: './src/setupTests.js' },
})
// src/setupTests.js:  import '@testing-library/jest-dom/vitest'
```

**React Compiler** (auto-memo, recommended). plugin-react 6 has no `babel` option:
```js
// npm i -D @rolldown/plugin-babel @babel/core babel-plugin-react-compiler
import babel from '@rolldown/plugin-babel'
import react, { reactCompilerPreset } from '@vitejs/plugin-react'
plugins: [react(), babel({ presets: [reactCompilerPreset()] })]
// experimental native: npm i -D oxc-transform-react; react({ compiler: true })
```

**Lint**: the template's oxlint lacks the compiler rules. Add `eslint @eslint/js globals eslint-plugin-react-hooks eslint-plugin-react-refresh`:
```js
import js from '@eslint/js'
import globals from 'globals'
import reactHooks from 'eslint-plugin-react-hooks'
import reactRefresh from 'eslint-plugin-react-refresh'
import { defineConfig, globalIgnores } from 'eslint/config'
export default defineConfig([globalIgnores(['dist']), {
  files: ['**/*.{js,jsx}'],
  extends: [js.configs.recommended, reactHooks.configs.flat.recommended, reactRefresh.configs.vite],
  languageOptions: { globals: { ...globals.browser, ...globals.vitest },
    parserOptions: { ecmaFeatures: { jsx: true } } } }]) // without it: `Parsing error: Unexpected token <`
```

## Removed APIs: never generate these
| Gone / legacy | Use |
|---|---|
| `ReactDOM.render`/`hydrate`, `unmountComponentAtNode` | `createRoot`/`hydrateRoot` (`react-dom/client`), `root.unmount()` |
| `findDOMNode`, string refs | `useRef` / callback refs |
| `Fn.defaultProps` (silently ignored, no warning!), `propTypes` | default params `({ size = 'md' })` |
| `forwardRef` (new code) | `ref` is a plain prop |
| `<Ctx.Provider>` (still works, to be deprecated) | `<Ctx value={v}>` |
| `useFormState` (react-dom) | `useActionState` (react) |
| `react-dom/test-utils`, react-test-renderer | `act` from `react`, Testing Library |

## Version-specific APIs
```jsx
import { use, useActionState, useOptimistic, useEffectEvent, Activity,
  ViewTransition, addTransitionType, startTransition, Fragment, Suspense } from 'react'
import { useFormStatus } from 'react-dom'

function Input({ ref, ...props }) { return <input ref={ref} {...props} /> }

<div ref={node => {                    // return = cleanup
  const ro = new ResizeObserver(onResize); ro.observe(node)
  return () => ro.disconnect()
}} />
// use a block body; `ref={n => (x = n)}` returns a value (TS error)

const theme = use(ThemeContext)        // OK after early return / in if

// Actions: async fn as <form action>
async function save(prevState, formData) {
  const name = formData.get('name')
  if (!name) return { error: 'Name required', name } // echo input back
  await api.save(name); return { error: null, name }
}
function NameForm() {
  const [state, formAction, isPending] = useActionState(save, { error: null, name: '' })
  return <form action={formAction}>
    <input name="name" defaultValue={state.name} />
    <Submit />{state.error && <p role="alert">{state.error}</p>}
  </form>
}
function Submit() {                    // must be a CHILD of the <form>
  const { pending } = useFormStatus()
  return <button disabled={pending}>Save</button>
}
// React resets uncontrolled fields after EVERY action, even on error: echo values via defaultValue
// manual dispatch: startTransition(() => formAction(fd))

const [optimistic, addOptimistic] = useOptimistic(likes, (cur, n) => cur + n)
// only inside an action / startTransition

const data = use(promise)              // suspends → <Suspense>
// promise must be created outside render (loader, cache, parent); a new one per render loops

const onConnected = useEffectEvent(() => notify(theme)) // latest props, not a dep
useEffect(() => { const c = connect(roomId); c.on('open', onConnected); return () => c.close() }, [roomId])

<Activity mode={open ? 'visible' : 'hidden'}><Panel /></Activity> // keeps state; effects off

startTransition(() => { addTransitionType('next'); setPage(p => p + 1) })
<ViewTransition enter={{ next: 'slide-in' }} exit={{ next: 'slide-out' }}><Page key={page} /></ViewTransition>
// animates only Transition/Suspense/useDeferredValue updates

<Fragment ref={fragRef}>{items}</Fragment> // .focus() .observeUsing(observer) .addEventListener
```
- `<title>`, `<meta>`, `<link>` anywhere are hoisted to `<head>`. `<link rel="stylesheet" href precedence="default">` dedupes and orders.
- SSR: `use(browser())` (from `react-dom`) renders the Suspense fallback on the server and the content on the client.
- Error boundaries are still classes (`getDerivedStateFromError`), or use `react-error-boundary`.

## Idioms the compiler and lint rules enforce
- Derive values during render. Never `useEffect(() => setX(f(a)), [a])` (`set-state-in-effect`). Reset state on identity change with `<Profile key={userId} />`.
- Render must be pure: no `ref.current` read or write (`refs`), no `Date.now()`/`Math.random()` (`purity`; use a `useState(() => …)` initializer), no mutating props, state or JSX-passed values.
- Never define a component inside another (`static-components`); it remounts.
- User-caused logic goes in handlers. Effects only sync external systems, with cleanup; StrictMode runs them twice in dev, so don't work around that.
- External stores and browser APIs: `useSyncExternalStore(subscribe, getSnapshot)`.
- Fetch in an effect only with `AbortController` cleanup (`return () => c.abort()`), or use a data library or `use(promise)`.
- With the Compiler, skip `useMemo`/`useCallback`/`memo`. Without it, memoize only measured hot paths.

## Errors → fixes
- `React Hook "useX" is called conditionally` → hooks above every early return (`use` exempt).
- `An async function with useActionState was called outside of a transition` → `<form action>` or `startTransition`.
- `An optimistic state update occurred outside a transition or action` → same fix.
- `A suspended resource finished loading inside a test, but … not wrapped in act` → `await act(async () => { render(<App />) })`, then `findBy*`.
- `ResizeObserver/IntersectionObserver is not defined` (jsdom) → stub in setupTests.
- `Hydration failed because the server rendered HTML didn't match` → no `window`/`Date`/random in render; `useId`, `use(browser())`.
- `Too many re-renders` → `onClick={setX(1)}` calls it in render; use `() => setX(1)`.

Tests: `const user = userEvent.setup(); await user.click(getByRole('button'))`, then `await findByText()`.
