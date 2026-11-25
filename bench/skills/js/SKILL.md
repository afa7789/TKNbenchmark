---
name: js
description: "Version-correct, idiomatic JavaScript for the installed toolchain (Node.js v26.13.1): API, build commands, idioms and pitfalls. Use whenever writing, building, testing or fixing JavaScript code."
---

# JavaScript on Node.js 26 (LTS, v26.13)

V8 14.6, npm 11, undici 8. No bundled Corepack.

## Layout
`src/index.js`, `src/lib/*.js`, `test/*.test.js` (`node --test` finds `**/*.test.{js,mjs,cjs,ts}` and `test/**`), `eslint.config.js`, optional `tsconfig.json` (type-check only).
```json
{ "type": "module", "engines": { "node": ">=26" },
  "exports": { ".": "./src/index.js", "./package.json": "./package.json" },
  "imports": { "#lib/*": "./src/lib/*" }, "files": ["src"],
  "scripts": { "start": "node --env-file-if-exists=.env src/index.js",
    "dev": "node --watch --env-file-if-exists=.env src/index.js",
    "test": "node --test", "lint": "eslint .", "typecheck": "tsc" } }
```
- No `"type"`: `MODULE_TYPELESS_PACKAGE_JSON` warning and a reparse.
- Unlisted `exports` paths throw `ERR_PACKAGE_PATH_NOT_EXPORTED`. Order: `"types"` first, `"default"` last. Self-import by name works.
- Aliases go in `#`-imports (`'#lib/math.js'`). Node ignores tsconfig `paths`.
- Without `files`, tests get published (`npm pack --dry-run`).
- `node --run x`: no pre/post scripts, no `npm_package_*` vars.

## ESM errors
- Relative specifiers need the extension (`./util.js`). No index lookup, else `ERR_MODULE_NOT_FOUND`.
- No `__dirname`/`__filename`/`require`; use `import.meta.dirname`, `import.meta.filename`, `createRequire(import.meta.url)`, and `import.meta.main` (= `require.main === module`).
- `import cfg from './c.json' with { type: 'json' }`. Without `with`: `ERR_IMPORT_ATTRIBUTE_MISSING`. `assert {}` is a SyntaxError.
- `require(esm)` is synchronous and returns the namespace (default export at `.default`). If the graph has top-level await: `ERR_REQUIRE_ASYNC_MODULE`.
- Always use the `node:` prefix. `process.getBuiltinModule('node:fs')` loads a builtin synchronously when the import is conditional.
- Loader hooks: `module.registerHooks()`. `module.register()` is runtime-deprecated.

## TypeScript, no build
`node app.ts` strips types (stable, on by default) but does **not** type-check, so also run `tsc` (TS 7). `enum`, `namespace` and parameter properties throw `ERR_UNSUPPORTED_TYPESCRIPT_SYNTAX`; `--experimental-transform-types` is removed. Use `import type` and `.ts` specifiers. Never stripped in `node_modules`: publish `.js`.
tsconfig: `"module":"nodenext","target":"esnext","noEmit":true,"strict":true,"erasableSyntaxOnly":true,"verbatimModuleSyntax":true,"allowImportingTsExtensions":true,"types":["node"]`. To type-check JS through JSDoc, add `"allowJs":true,"checkJs":true`.

## Removed or deprecated: don't emit
| Old | Use |
|---|---|
| `res.writeHeader()` (removed in 26) | `res.writeHead()` |
| `_stream_*` modules (removed in 26) | `node:stream` |
| `fs.F_OK`… (removed) | `fs.constants.F_OK` |
| `SlowBuffer`, `new Buffer()` | `Buffer.alloc` |
| `util.isDate`, `util.log`… | `util.types.*`, `console.log` |
| `url.parse()` (DEP0169) | `new URL()`, `URL.parse()` → `null`, `URL.canParse()` |
| `fs.rmdir(p,{recursive})` | `fs.rm(p,{recursive:true,force:true})` |
| `spawn(c,args,{shell:true})` (DEP0190) | `execFile` |
| sqlite `DatabaseSync`/`StatementSync` | `Database`/`Statement` (26.11+) |

`localStorage` is `undefined` unless you pass `--localstorage-file=path`.

## Language (no flags)
`Temporal`, `using`/`await using`/`DisposableStack`, `Map#getOrInsert`/`getOrInsertComputed`, `Iterator.concat`, iterator helpers (`.values().filter().map().take().toArray()`), Set `union`/`intersection`/…, `Object.groupBy`, `Promise.try`, `RegExp.escape`, `Error.isError`, `Uint8Array.fromBase64`/`fromHex`/`#toBase64`/`#toHex`, `Array.fromAsync`, `Float16Array`. **Not available:** `Math.sumPrecise`.
```js
Temporal.PlainDate.from('2026-01-31').add({ months: 1 }).toString(); // '2026-02-28'
Temporal.ZonedDateTime.from('2026-03-08T01:30[America/New_York]').add({ hours: 1 }); // DST-safe
Temporal.Duration.from({ hours: 1, minutes: 30 }).total('minutes'); // 90
Temporal.PlainDate.compare(a, b);                     // not < or ===
new Date(Temporal.Now.instant().epochMilliseconds);   // to legacy Date
groups.getOrInsertComputed(key, () => []).push(item);
```

## Stdlib idioms
```js
import { glob } from 'node:fs/promises';  import { pipeline } from 'node:stream/promises';
import { setTimeout as sleep } from 'node:timers/promises';
import { parseArgs, styleText, debounce, promisify } from 'node:util';
for await (const f of glob('src/**/*.js', { exclude: (p) => p.includes('node_modules') })) {}
await pipeline(createReadStream(a), createGzip(), createWriteStream(b));   // not .pipe()
for await (const line of createInterface({ input: createReadStream(p), crlfDelay: Infinity })) {}
const res = await fetch(url, { signal: AbortSignal.timeout(5000) });
if (!res.ok) throw new Error(`HTTP ${res.status}`);   // non-2xx never rejects
const { values, positionals } = parseArgs({ allowPositionals: true,
  options: { verbose: { type: 'boolean', short: 'v' }, out: { type: 'string', default: 'dist' } } });
// unknown flag -> ERR_PARSE_ARGS_UNKNOWN_OPTION; styleText(['bold','red'], s) prints no color when not a TTY
const { stdout } = await promisify(execFile)('git', ['rev-parse', 'HEAD']);
```
```js
import { Database } from 'node:sqlite';            // synchronous, no deps
using db = new Database('app.db');                 // or ':memory:'
db.exec('CREATE TABLE IF NOT EXISTS t(id INTEGER PRIMARY KEY, name TEXT) STRICT');
db.prepare('INSERT INTO t(name) VALUES (?)').run('a');    // { changes, lastInsertRowid }
db.prepare('SELECT * FROM t WHERE id = $id').get({ id: 1 }); // row | undefined; .all() .iterate()
const sql = db.createTagStore(); sql.get`SELECT * FROM t WHERE name = ${n}`; // parameterized
```
Transactions: `exec('BEGIN')`, `COMMIT`, `ROLLBACK` in catch.

## node:test
```js
import { test, suite } from 'node:test';
suite('api', () => {
  test('http', async (t) => {
    const server = createServer(handler).listen(0); await once(server, 'listening');
    t.after(() => server.close());
    const res = await fetch(`http://127.0.0.1:${server.address().port}`);
    t.assert.deepStrictEqual(await res.json(), { ok: true });
  });
  test('mocks', (t) => {
    t.mock.timers.enable({ apis: ['setTimeout'] }); t.mock.timers.tick(1000);
    const fn = t.mock.fn(); fn(1); t.assert.equal(fn.mock.callCount(), 1);
    t.mock.method(obj, 'get', () => 2);
  });
});
```
- Prefer `t.assert`/`t.plan(n)`; under `checkJs` (TS2775) use `node:assert/strict`.
- `test.only` needs `--test-only`. `mock.module()` needs `--experimental-test-module-mocks`.
- `t.assert.snapshot()` fails until `--test-update-snapshots` writes the `.snapshot` file (commit it).
- Flags: `--test-name-pattern=re`, `--test-reporter=dot`, `--watch`, `--test-randomize`, `--experimental-test-coverage --test-coverage-lines=80`.

## Runtime fixes
- Use `process.exitCode = 1`; `process.exit()` truncates piped output.
- `TypeError: fetch failed`: the reason is in `err.cause.code` (`ECONNREFUSED`…). A timeout rejects with `TimeoutError`, an abort with `AbortError`.
- `emit('error')` with no listener throws; streams outside `pipeline` need `'error'` handlers.
- Match errors on `err.code`, not the message.
- Hang? `node --process-timeout=30s app.js` lists live handles, exits 124.
- `process.loadEnvFile()` mirrors `--env-file`; real env vars win.
- CPU work: `new Worker(new URL(import.meta.url), { workerData })`, pool size `os.availableParallelism()`.
- `--permission --allow-fs-read=./data --allow-net`; denied calls throw `ERR_ACCESS_DENIED`.

## Lint (ESLint 10, flat config only)
```js
import js from '@eslint/js'; import globals from 'globals'; import { defineConfig } from 'eslint/config';
export default defineConfig([{ ignores: ['coverage/'] },
  { files: ['**/*.js'], extends: [js.configs.recommended], languageOptions: { globals: globals.node } }]);
```

## Ship
CI: `npm ci && npm run lint && npm run typecheck && npm test`. Release: `npm version patch`, `npm publish --provenance` (CI OIDC). `.npmrc`: `min-release-age=3` (days), `ignore-scripts=true`.
