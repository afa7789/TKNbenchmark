---
name: ts
description: "Version-correct, idiomatic TypeScript for the installed toolchain (Node.js v26.13.1, which runs .ts files natively): API, build commands, idioms and pitfalls. Use whenever writing, building, testing or fixing TypeScript code."
---

# TypeScript on Node.js 26 + TypeScript 7

Node 26 LTS runs `.ts` directly; TypeScript 7.0.x is the Go-native `tsc` in the `typescript` package; use `@types/node@26`. Node **strips** types and never type-checks, so `tsc` is your type checker. You don't need tsx or ts-node.

## Node's strip-only mode: what fails at runtime
Node ignores `tsconfig.json`, refuses `.ts` in `node_modules`, and has no `.tsx` support. `--experimental-transform-types` was removed in 26.

| Don't write | Error | Write instead |
|---|---|---|
| `enum E {A}` | `ERR_UNSUPPORTED_TYPESCRIPT_SYNTAX` | `const E = {A:'a'} as const; type E = (typeof E)[keyof typeof E]` |
| `constructor(private x: T)` | same | declare the field and assign it |
| `namespace N { export const v = 1 }` | same | ES module |
| `import x = require('m')` | same | `import x from 'm'` |
| `<T>expr` | same | `expr as T` |
| decorators `@dec` | `SyntaxError` | no decorators without a build step |
| `import { User } from './u.ts'` (User is a type) | `does not provide an export named 'User'` | `import type { User }` / `import { f, type User }` |
| `import './util'` | `ERR_MODULE_NOT_FOUND` | `import './util.ts'` (extension required) |

`erasableSyntaxOnly` + `verbatimModuleSyntax` make `tsc` catch these (TS1294, TS1484).

## tsconfig: application (run from source, no emit)
```json
{
  "compilerOptions": {
    "target": "esnext", "module": "nodenext", "types": ["node"],
    "noEmit": true, "allowImportingTsExtensions": true,
    "erasableSyntaxOnly": true, "verbatimModuleSyntax": true,
    "noUncheckedIndexedAccess": true, "exactOptionalPropertyTypes": true,
    "noImplicitOverride": true, "skipLibCheck": true
  },
  "include": ["src", "test"]
}
```
`package.json`: `"type": "module"`, `"engines": {"node": ">=26"}`. Run it with `node src/main.ts`.

## tsconfig: library (emit JS + .d.ts)
In the base `tsconfig.json` (src+test), replace `allowImportingTsExtensions` with `"rewriteRelativeImportExtensions": true` and add `"declaration": true, "isolatedDeclarations": true`. Then add `tsconfig.build.json`:
```json
{ "extends": "./tsconfig.json",
  "compilerOptions": { "noEmit": false, "rootDir": "src", "outDir": "dist",
    "declaration": true, "declarationMap": true, "sourceMap": true },
  "include": ["src"] }
```
`./x.ts` is emitted as `./x.js`. Non-relative specifiers are not rewritten (`#a/x.ts` gives TS2877), so use relative imports. package.json:
```json
"type": "module", "files": ["dist"],
"exports": { ".": { "types": "./dist/index.d.ts", "default": "./dist/index.js" } }
```
Put `types` first; check with `npm pack --dry-run`. `isolatedDeclarations` requires explicit return types on exports (TS9007/9013/9017).

## TS 6/7 defaults and removals that trip agents
- `types` defaults to `[]`: TS2591 `Cannot find name 'process'`. Fix: `"types": ["node"]`.
- `rootDir` defaults to the tsconfig's directory: TS5011 when using `outDir` with `src/`. Fix: `"rootDir": "src"`.
- `strict` is on by default. The default `target` is `es2025`, which has **no Temporal types** (TS2304). Use `"target": "esnext"` or `lib` `esnext.temporal`.
- `noUncheckedSideEffectImports` is on: `import './nope.ts'` gives TS2882.
- Hard errors now: `baseUrl` (TS5102, use relative `paths`), `moduleResolution: node/node10/classic` (use `nodenext`/`bundler`), `esModuleInterop: false`, `target: es5`, `downlevelIteration`, `outFile`, `module amd/umd/system/none`, `assert {}` (use `with {}`), `module Foo {}` (use `namespace`).
- `tsc file.ts` when a tsconfig is present gives TS5112. Use `tsc -p <config>` or `--ignoreConfig`.
- New flags: `--checkers N` (default 4), `--builders N`, `--singleThreaded`.
- **TS 7 has no compiler API**, so typescript-eslint (peer `typescript <6.1`) crashes with it. Install TS 6 under the `typescript` name:
  `npm i -D "typescript@npm:@typescript/typescript6@^6" "@typescript/native@npm:typescript@^7"`. Then `tsc` is 7, `tsc6` is 6, and ESLint works.
- Exist in Node but have no types yet: `Iterator.concat`, `util.debounce/throttle`.

## Layout & scripts
```
src/  main.ts  lib.ts      test/  lib.test.ts      tsconfig.json  package.json
```
```json
"scripts": { "start": "node src/main.ts", "dev": "node --watch --env-file-if-exists=.env src/main.ts",
  "check": "tsc", "test": "node --test", "lint": "eslint .", "build": "tsc -p tsconfig.build.json" }
```
`node --run check` is faster than `npm run`. A bare `node --test` finds `**/*.test.ts`, `test/**/*.ts` and similar. Aliases: `paths` is ignored at runtime, so use package.json `"imports": {"#/*": "./src/*"}` with `import { x } from '#/lib.ts'` (apps only). Without `"type": "module"`, files are CJS: TS1470 for `import.meta`, TS1309 for top-level await.

## Tests (node:test)
```ts
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { greet } from '../src/lib.ts';
describe('greet', () => {
  it('works', (t) => {
    assert.equal(greet('a'), 'hi a');
    const fn = t.mock.fn((x: number) => x * 2); fn(2);
    assert.equal(fn.mock.callCount(), 1);
    assert.deepEqual(fn.mock.calls[0]?.arguments, [2]);
    t.mock.timers.enable({ apis: ['setTimeout'] }); // then t.mock.timers.tick(ms)
    t.assert.snapshot({ a: 1 }); // first run: --test-update-snapshots
  });
  it('rejects', async () => { await assert.rejects(p(), TypeError); });
});
```
Flags: `--test-name-pattern=re`, `--test-only`, `--watch`, `--test-reporter=dot`, `--experimental-test-coverage --test-coverage-exclude='test/**' --test-coverage-lines=90`. `mock.module()` needs `--experimental-test-module-mocks`.

## Node 26 / ES2025+ APIs to prefer
```ts
import { parseArgs, styleText, parseEnv } from 'node:util';
import { glob, readFile } from 'node:fs/promises';
import { randomUUIDv7 } from 'node:crypto';
import { DatabaseSync } from 'node:sqlite'; // runtime alias `Database` is not in @types yet
import pkg from '../package.json' with { type: 'json' };

const { values } = parseArgs({ options: { name: { type: 'string', short: 'n', default: 'x' } } });
console.log(styleText(['bold', 'green'], 'ok'));
for await (const f of glob('src/**/*.ts')) {}
const here = import.meta.dirname; if (import.meta.main) { /* entry point */ }
{ using db = new DatabaseSync(':memory:');  // closed at block end
  db.prepare('select ? as v').get(1); }      // rows: null-prototype objects
await using stack = new AsyncDisposableStack(); stack.defer(async () => {});
const m = new Map<string, number[]>(); m.getOrInsert('k', []).push(1); m.getOrInsertComputed('j', () => []);
const due = Temporal.PlainDate.from('2026-01-31').add({ months: 1 }); // 2026-02-28
Temporal.Now.instant().toZonedDateTimeISO('Europe/Lisbon');
Error.isError(e); Promise.try(fn); RegExp.escape(s); Uint8Array.fromBase64(b).toHex();
const res = await fetch(url, { signal: AbortSignal.timeout(5000) });
const data: unknown = await res.json(); // json() is any: validate
process.loadEnvFile('.env'); // or --env-file=.env
```
- Prefer `Temporal` over `Date` math, `structuredClone`, global `fetch`/`WebSocket`, `node:` imports, and `using` for anything disposable.
- `require(esm)` works without flags. `module.register()` is deprecated (DEP0205); use `module.registerHooks()`.
- `localStorage` is `undefined` without `--localstorage-file`. `writeHeader()` and `_stream_*` modules are gone.
- Workers run `.ts`: `new Worker(new URL('./w.ts', import.meta.url))`.

## Errors → fixes
- TS18046 `'e' is of type 'unknown'` in a catch → narrow with `Error.isError(e)`; wrap with `new Error('msg', { cause: e })`.
- TS2532/TS2322 `possibly 'undefined'` from `arr[0]`/`rec[k]` → `?.`, `??` or a guard, not `!`.
- TS2379 (`exactOptionalPropertyTypes`) → omit the key, or type it `a?: T | undefined`.
- TS2835 `need explicit file extensions` → add `.ts`.
- TS5069 `isolatedDeclarations` without `declaration` → add `"declaration": true`.
- `MODULE_TYPELESS_PACKAGE_JSON` warning → add `"type": "module"`.
- `tsc` still emits when there are errors, so gate CI on its exit code.
