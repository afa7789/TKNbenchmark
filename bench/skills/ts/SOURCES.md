# Sources

## Official documentation and release notes
- https://nodejs.org/api/typescript.html: Node 26.13.1 type-stripping rules, the recommended tsconfig, unsupported syntax, the `.ts` extension requirement, the `node_modules` restriction, and the advice to use `#` subpath imports instead of `paths`.
- https://nodejs.org/blog/release/v26.0.0: Temporal on by default, V8 14.6 (`Map#getOrInsert`, `Iterator.concat`), Undici 8, removal of `--experimental-transform-types`, `writeHeader` and `_stream_*`, and the `module.register()` deprecation.
- https://github.com/nodejs/node/blob/main/doc/changelogs/CHANGELOG_V26.md (raw file): semver-minor additions in 26.1 through 26.13, e.g. sqlite `Database`/`Statement` renames, `crypto.randomUUIDv7`, `util.debounce/throttle`, `--process-timeout`, `--test-coverage-include-all`, the experimental `node:ffi`, and 26.13 becoming LTS.
- https://nodejs.org/api/test.html: `node --test` default globs (including `.ts`), mocking APIs, mock timers, `t.assert.snapshot`, coverage and reporter flags.
- https://nodesource.com/blog/nodejs-v26-is-here: a summary of the Node 26 headline features (Temporal, V8 14.6, Undici 8).
- https://devblogs.microsoft.com/typescript/announcing-typescript-7-0/: TS 7 ships as `typescript`/`tsc`, the new defaults (`types: []`, `rootDir`, `strict`), removed options, `--checkers`/`--builders`/`--singleThreaded`, no API, and the `@typescript/typescript6` alias setup.
- https://devblogs.microsoft.com/typescript/announcing-typescript-7-0-beta: background on the native port and the list of options that became hard errors.
- https://devblogs.microsoft.com/typescript/announcing-typescript-6-0/: the 6.0 default changes (target `es2025`), Temporal types via `esnext`/`esnext.temporal`, `#/` subpath imports, and the full deprecation list.

## Style guides
- https://google.github.io/styleguide/tsguide.html: named exports, no namespaces or `require`, `import type`, `unknown` over `any`, throwing only `Error`, `as` rather than angle-bracket casts, and avoiding `!`.
- https://www.totaltypescript.com/tsconfig-cheat-sheet: the widely used tsconfig baseline (`verbatimModuleSyntax`, `noUncheckedIndexedAccess`, `noImplicitOverride`, `moduleDetection`) and the app, library and bundler variants.

## Tooling
- https://typescript-eslint.io/getting-started/: the flat `eslint.config` with `defineConfig` and the recommended, strict and stylistic configs.
- https://github.com/typescript-eslint/typescript-eslint/issues/12518: typescript-eslint does not work with TS 7 (no API). The fix is to keep TS 6 aliased as `typescript`.
- https://tsdown.dev/options/lint: library publishing checks (publint, arethetypeswrong) and putting `types` first in `exports`.

## Community agent rules
- https://dev.to/olivia_craft/claudemd-for-typescript-and-nodejs-13-rules-that-make-ai-write-type-safe-production-ready-code-47hm: what CLAUDE.md authors agree on (strict mode, no `any`, validation at boundaries, `Error` subclasses, explicit return types on exports). Its advice to use tsconfig `paths` is contradicted for native Node, so the skill uses subpath imports instead.
- https://raw.githubusercontent.com/PatrickJS/awesome-cursorrules/main/README.md: a survey of common TypeScript cursor rules (prefer `unknown`, strict config, avoid enums and namespaces).
- https://raw.githubusercontent.com/mattpocock/skills/main/README.md: how engineering skills for agents are structured (concise, action-oriented, test-first).

## Local verification (installed toolchain)
- Node v26.13.1, typescript@7.0.2, @typescript/typescript6@6.0.3, @types/node@26.6.10, eslint@10 and typescript-eslint@8.74 were checked in a scratch project. Every snippet, flag and error code in SKILL.md was produced by building or running it locally.
