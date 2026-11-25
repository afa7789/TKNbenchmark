# Sources

## Official React documentation and release notes
- https://react.dev/blog/2026/09/09/react-19-3: 19.3 features: stable `<ViewTransition>`, `addTransitionType`, Fragment refs (FragmentInstance methods), `browser()` from react-dom, Trusted Types, changelog.
- https://react.dev/blog/2025/10/01/react-19-2: `<Activity mode>`, `useEffectEvent` (not a dependency), `cacheSignal`, partial prerendering APIs, `useId` prefix `_r_`, eslint-plugin-react-hooks flat config.
- https://react.dev/blog/2024/12/05/react-19: Actions, `useActionState`, `useFormStatus` (react-dom), `useOptimistic`, `use`, ref as prop, ref cleanup, `<Context>` as provider, document metadata, stylesheet `precedence`, preload APIs.
- https://react.dev/blog/2024/04/25/react-19-upgrade-guide: removed APIs and their replacements (render/hydrate, findDOMNode, string refs, defaultProps/propTypes on functions, test-utils `act`), root `onUncaughtError`/`onCaughtError`, ref-callback implicit-return issue.
- https://react.dev/blog: release timeline (19.0 → 19.2 → Compiler 1.0 → 19.3) and the Create React App sunset, which recommends Vite.
- https://react.dev/reference/rules: Rules of React (purity, immutability, rules of hooks). Used as the official style guide.
- https://react.dev/learn/you-might-not-need-an-effect: derive during render, reset via `key`, logic in handlers, `useSyncExternalStore`, fetch with cleanup.

## Toolchain
- https://vite.dev/blog/announcing-vite8: Rolldown/Oxc replace esbuild/Rollup, Node 20.19+/22.12+, plugin-react v6 drops Babel.
- https://github.com/vitejs/vite-plugin-react/blob/main/packages/plugin-react/README.md: plugin options, `reactCompilerPreset` with `@rolldown/plugin-babel`, experimental `compiler: true` using `oxc-transform-react`.
- https://recca0120.github.io/en/2026/04/14/react-compiler-vite-v6/: confirms the `babel` option was removed in v6 and the compiler is set up through `@rolldown/plugin-babel`.
- https://oxc.rs/blog/2026-08-18-react-compiler-support: native Oxc React Compiler is experimental and its defaults are aligned with Babel React Compiler v1.
- https://testing-library.com/docs/react-testing-library/setup: RTL with Vitest (`globals: true` for auto-cleanup, setupFiles).
- `npm create vite@latest -- --template react` (run locally): current template layout, scripts, `main.jsx`, and its oxlint config.
- The installed `eslint-plugin-react-hooks` 7.1.1 README: flat config `reactHooks.configs.flat.recommended` and the list of compiler-powered rules.

## Community agent skills and rules
- https://skills.sh/noklip-io/agent-skills/react-19: agrees on createRoot-only, hooks-only, Context via `createContext`, upgrade through 18.3.
- https://raw.githubusercontent.com/vercel-labs/agent-skills/main/skills/react-best-practices/AGENTS.md (Vercel react-best-practices skill): re-render rules (derive state, no nested components, functional setState, lazy init, transitions, useDeferredValue, Activity, useEffectEvent).
- https://skills.sh/topic/react: survey of published React skills. Common themes are no forwardRef, no effects for derived state, and compiler-first memoization.

## Local verification (scratch project, since deleted)
All of the following were checked by building with `vite build`, running Vitest + jsdom + RTL, linting with ESLint, and rendering with Node SSR:
- export lists of react, react-dom, react-dom/client, react-dom/server and react-dom/static 19.3.1;
- the Babel React Compiler build;
- runtime warning texts (useActionState and useOptimistic outside a transition, the act warning, keys, "Too many re-renders");
- that function-component `defaultProps` is silently ignored;
- that uncontrolled forms are reset even when the action returns an error;
- that JSX in `.js` fails under Vite 8;
- that jsdom lacks `ResizeObserver`;
- the Vite 8 `rolldownOptions` and `oxc` option names.
