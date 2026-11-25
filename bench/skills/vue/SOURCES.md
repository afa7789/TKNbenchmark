# Sources

## Official docs and release notes
- https://blog.vuejs.org/posts/vue-3-5 — Vue 3.5 features: reactive props destructure, useTemplateRef, useId, data-allow-mismatch, lazy hydration (hydrateOnVisible), Teleport `defer`, onWatcherCleanup. Its Teleport example uses `target` where the prop is actually `to`.
- https://raw.githubusercontent.com/vuejs/core/main/CHANGELOG.md — 3.5.x patch behavior changes up to 3.5.46 (provide-after-mount warning, watcher/transition fixes). Confirmed 3.6 is not stable.
- https://vuejs.org/style-guide/ — official style guide priorities: multi-word names, keyed v-for, no v-if with v-for, detailed prop definitions.
- https://vuejs.org/guide/typescript/composition-api — typing useTemplateRef (InstanceType, ComponentExposed for generic components), InjectionKey, defineEmits tuple syntax.
- https://vite.dev/guide/migration — Vite 7→8 breaking changes: rolldownOptions, oxc, Oxc/Lightning CSS minifiers, manualChunks object form removed, new baseline browser targets.
- https://vite.dev/blog/announcing-vite8 — Vite 8 is Rolldown-based, with a compatibility layer for esbuild/rollupOptions config.
- https://github.com/vuejs/pinia/releases — Pinia 4.0: ESM-only, @vue/devtools-api v8 peer, no API changes. 4.1: getStores(). @pinia/testing 2.x.
- https://vuejs.school/community/blog/pinia-4-what-changed-and-what-to-do — Pinia 4 migration notes (TS >= 5.6, Jest must transform ESM).
- https://router.vuejs.org/guide/migration/v4-to-v5 — Router 5: no core breaking changes. File-based routing merged in (`vue-router/vite`, `vue-router/auto-routes`, `vue-router/experimental`).
- https://github.com/vuejs/router/releases — Router 5.0–5.5.1 changes (typed definePage, scroll restoration, query normalization).
- https://vitest.dev/guide/migration — Vitest 5 changes: top-level-only vi.mock, clearMocks default, awaited resolves/rejects, Node >= 22.12.

## Community agent skills / rules
- https://raw.githubusercontent.com/vuejs-ai/skills/main/README.md — catalog of Vue-team-adjacent agent skills (best practices, router, pinia, testing, debug). Rules are kept only when a baseline agent fails without them.
- https://raw.githubusercontent.com/vuejs-ai/skills/main/skills/vue-best-practices/SKILL.md — consensus defaults: `<script setup lang="ts">`, single source of truth, computed over watchers, typed props/emits, InjectionKey.
- https://raw.githubusercontent.com/vuejs-ai/skills/main/skills/vue-best-practices/references/reactivity.md — reactivity gotchas: shallowRef, no reactive destructure, watch getters, pure computed, cleanup of stale async.
- https://github.com/antfu/skills — antfu's Vue/Vite/Pinia/Vitest/pnpm skill collection. Confirms a TS + ESM + Composition API focus.
- https://vueschool.io/articles/vuejs-tutorials/vue-agent-skills-for-reliable-ai-development/ — keep project AGENTS.md/CLAUDE.md lean and put framework knowledge in skills.

## Tooling compatibility
- https://github.com/vuejs/language-tools/discussions/6121 — vue-tsc does not work with TypeScript 7 (ERR_PACKAGE_PATH_NOT_EXPORTED). Reproduced locally; stay on TS 6.
- https://www.npmjs.com/package/create-vue — `npm create vue@latest` flags (--ts --router --pinia --vitest --eslint --bare), checked with `create-vue --help` (3.24.0).

## Local verification (scratch project, deleted afterwards)
- Scaffolded with create-vue 3.24.0 and pinned vue 3.5.46, vite 8.3.8, @vitejs/plugin-vue 6.0.11, pinia 4.1.0 (plus vue-router 5.5.1, vitest 5.1.2, @pinia/testing 2.0.2, vue-tsc 3.3.14, TS 6.0.3).
- Ran vue-tsc, vite build and vitest on probe components covering every snippet in SKILL.md: generic SFCs, defineModel modifiers, slots shorthand, useTemplateRef, watch pause/resume/deep, Pinia setup store/storeToRefs/createTestingPinia, file-based routing with typed useRoute, and rolldownOptions codeSplitting.
- Error texts in SKILL.md were captured from @vue/compiler-sfc and runtime-core output, and from Pinia, @pinia/testing and Vitest failures.
