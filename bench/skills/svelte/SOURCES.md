# Sources

## Official documentation and release notes
- https://svelte.dev/llms.txt — index of the official LLM-oriented doc bundles; used to find the Svelte-only bundle.
- https://svelte.dev/docs/svelte/llms.txt — full Svelte 5 docs. Used for runes ($state/.raw/.snapshot/.eager, $derived/.by and overrides, $effect/.pre/.pending/.root, $props/.id, $bindable, $inspect.trace), snippets, `{@attach}`, `{let/const}` declaration tags (5.56+, `{@const}` now legacy), clsx `class`, function bindings, `<svelte:boundary>`, await expressions, `fork`/`settled`, `hydratable`, createContext, testing, and the error/warning code reference.
- https://svelte.dev/docs/svelte/best-practices — the official best-practices page (same content as the "Best practices" section of the bundle). Source of the "avoid legacy features" list, keyed-each, `$state.raw` for API data, and `createContext` over get/setContext.
- https://github.com/sveltejs/svelte/releases — release notes for 5.56.10–5.59.2: custom renderer API (5.59), `getAbortSignal()` must be called before `await` (5.58.1, breaking in async mode), `createContext` `has` and `<select defaultValue>` (5.57).
- https://raw.githubusercontent.com/sveltejs/svelte/main/packages/svelte/CHANGELOG.md — minor-release features 5.40–5.59 with versions: createContext 5.40, $state.eager 5.41, fork 5.42, hydratable 5.44, function-valued `runes` compiler option 5.54, declaration tags 5.56.
- https://raw.githubusercontent.com/sveltejs/vite-plugin-svelte/main/packages/vite-plugin-svelte/CHANGELOG.md — v7 needs Vite 8 and svelte ≥ 5.46.4, removed deprecated options (`hot` → `compilerOptions.hmr`), v6 TS preprocessing needs `verbatimModuleSyntax`, ESM-only config.
- https://svelte.dev/docs/cli/llms.txt — `sv create` (`--template minimal|demo|library|addon`, `--types ts|jsdoc`, `--add`), `sv add vitest`, `sv check`.
- https://svelte.dev/docs/ai/llms.txt — official AGENTS.md prompt, `svelte-file-editor` subagent, and the `npx @sveltejs/mcp svelte-autofixer <file> --svelte-version <v>` CLI.

## Style guides / agent rules published by Svelte developers
- https://github.com/sveltejs/ai-tools/tree/main/tools/skills — official Svelte team agent skills (`svelte-core-bestpractices`, `svelte-code-writer`); confirmed that they mirror the docs' best-practices page and recommend an autofixer loop.
- https://raw.githubusercontent.com/spences10/sveltest/main/AGENTS.md — community AGENTS.md (sveltest): colocated tests, run tests and lint after changes, keep instructions to durable non-obvious decisions.
- https://awesome-copilot.github.com/instruction/svelte/ — widely copied Copilot instructions for Svelte 5. Agrees on runes, `$derived` over `$effect`, attachments and createContext, but still recommends slots and `class:`. Treated as an example of outdated advice to correct.

## Project setup as practiced today
- https://github.com/vitejs/vite/tree/main/packages/create-vite/template-svelte-ts — current official Vite template: `mount()` entry, `svelte()` plugin, `svelte-check` script, TypeScript ~6, `@tsconfig/svelte`.
- https://github.com/sveltejs/cli/tree/main/packages/sv/src/create/templates/minimal — current `sv create` template: forces runes for project files with `runes: ({ filename }) => filename.split(/[/\\]/).includes('node_modules') ? undefined : true`.
- https://svelte.dev/docs/svelte/runtime-errors — official explanations of `effect_update_depth_exceeded` and `state_unsafe_mutation`, cross-checked against a web search on common rune pitfalls.

## Local verification (installed toolchain, scratch project since deleted)
- svelte 5.59.1, vite 8.3.8, @sveltejs/vite-plugin-svelte 7.3.2, svelte-check 4.7.8, vitest 5.1.2, jsdom, @testing-library/svelte 5.4.2. Checked the exports of every `svelte/*` module, the type signatures (`createContext` returns `[get, set, has]`, Spring/Tween `.of`/`.set`/`.target`), and ran `vite build`, `vite build --ssr`, svelte-check and vitest on components that use every pattern in SKILL.md. Every compiler and runtime error code listed in SKILL.md was reproduced.
