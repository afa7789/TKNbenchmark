# Sources

- https://nodejs.org/blog/release/v26.0.0 — Node 26 breaking changes: Temporal on by default, V8 14.6 (`getOrInsert`, `Iterator.concat`), `writeHeader` and `_stream_*` removed, `module.register()` runtime-deprecated, `--experimental-transform-types` removed.
- https://nodejs.org/blog/release/v25.0.0 — Node 25 removals (`fs.F_OK`…, `SlowBuffer`, `assert.CallTracker`, `rmdir` recursive), Corepack no longer distributed, `--allow-net`, Web Storage enabled.
- https://raw.githubusercontent.com/nodejs/node/main/doc/changelogs/CHANGELOG_V26.md — every 26.x minor through 26.13.1 LTS: sqlite `Database`/`Statement` rename (26.11), `--process-timeout`, `util.debounce/throttle`, `node:ffi`, test runner randomization, `Buffer.poolSize` 64 KiB.
- https://nodejs.org/docs/latest-v26.x/api/sqlite.html — `node:sqlite` API: constructor options, `prepare/run/get/all/iterate`, `createTagStore`, `Symbol.dispose`, DEP0210/DEP0211 aliases.
- https://nodejs.org/en/learn/typescript/run-natively — type stripping is on by default, does no type-checking, and needs `erasableSyntaxOnly`.
- https://www.skillsdirectory.com/skills/xobotyi-nodejs — published Node agent skill with per-version notes (24/25/26): `exports` semantics, `node --run` differences, `process.exitCode`, fetch timeouts, test-runner flags, supply-chain `.npmrc` settings.
- https://skills.sh/mcollina/skills/node — Node TSC member's skill: use type stripping instead of ts-node/tsx, `import type`, no enums or parameter properties, `.ts` extensions.
- https://app.unpkg.com/agent-rules@1.4.2/files/__template__/nodejs/nodejs-dev/modern-nodejs-conventions.md — agent rules on modern Node conventions: ESM by default, the `node:` prefix, `node:test`, `--watch`, `--env-file`, worker threads.
- https://raw.githubusercontent.com/goldbergyoni/nodebestpractices/master/README.md — Node Best Practices (2026 edition): throw only `Error`s, handle `'error'` events, `npm ci` and the lockfile, port 0 in tests, `node:` imports, `execFile` over a shell.
- https://github.com/airbnb/javascript — the most widely followed JS style guide (const/no var, object/array idioms, `Object.hasOwn`, template literals) and the ESLint rules behind it.
- https://eslint.org/docs/head/use/migrate-to-10.0.0 — ESLint 10 supports flat config only; `defineConfig` from `eslint/config` with `js.configs.recommended`.
- https://socket.dev/blog/npm-introduces-minimumreleaseage-and-bulk-oidc-configuration — npm's release-age cooldown and OIDC trusted publishing (I verified the `min-release-age` semantics in the installed npm 11.20 docs).
- https://github.blog/changelog/2026-02-18-npm-bulk-trusted-publishing-config-and-script-security-now-generally-available/ — npm trusted publishing and install-script security controls.
- https://raw.githubusercontent.com/Taiizor/agents-md-cookbook/790e0ba0d9c7fc9b96992bd68f08e9bfcb4c217e/templates/typescript-node/AGENTS.md — sample AGENTS.md for a Node project: `node:test` + `node:assert/strict`, `.js` extensions in ESM imports.

Verification: I checked every API, flag, error code and command in SKILL.md against the installed Node v26.13.1, npm 11.20.0, ESLint 10.15 and TypeScript 7.0.2 by running snippets in a scratch directory, which I have since deleted.
