// Single source of truth for what the benchmark runs.
import { existsSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

export const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
export const RUNS = join(ROOT, 'runs')
export const WORK = process.env.TKN_WORK ?? join(tmpdir(), 'tknbench')

export const MODEL = 'claude-opus-5-5'
export const EFFORT = 'high'
export const TOOLS = 'Bash,Read,Edit,Write'
export const RUN_TIMEOUT_MS = 30 * 60 * 1000

const JVM_NOTE = 'On the JVM, ./app may be a small launcher script that runs java.'
const launcher = (bin) => `./app may be a small launcher script that runs ${bin}.`

export const LANGS = {
  c: { label: 'C', name: 'C (C17)', version: ['clang', '--version'] },
  cpp: { label: 'C++', name: 'C++ (C++20)', version: ['clang++', '--version'] },
  rust: { label: 'Rust', name: 'Rust (edition 2024)', version: ['rustc', '--version'] },
  go: { label: 'Go', name: 'Go', version: ['go', 'version'] },
  nim: { label: 'Nim', name: 'Nim', version: ['nim', '--version'] },
  zig: { label: 'Zig', name: 'Zig', version: ['zig', 'version'] },
  swift: { label: 'Swift', name: 'Swift', version: ['sh', '-c', 'swift --version 2>&1 | grep "Swift version"'] },
  java: { label: 'Java', name: 'Java', version: ['java', '-version'], note: JVM_NOTE },
  kotlin: { label: 'Kotlin', name: 'Kotlin (JVM)', version: ['kotlinc', '-version'], note: JVM_NOTE },
  csharp: { label: 'C#', name: 'C# (.NET)', version: ['sh', '-c', 'echo ".NET SDK $(dotnet --version)"'] },
  odin: { label: 'Odin', name: 'Odin', version: ['sh', '-c', 'odin version | sed "s|.*odin version|Odin|"'] },
  ocaml: { label: 'OCaml', name: 'OCaml', version: ['ocaml', '-version'] },
  haskell: { label: 'Haskell', name: 'Haskell (GHC)', version: ['ghc', '--version'] },
  js: { label: 'JavaScript', name: 'JavaScript (Node.js)', version: ['sh', '-c', 'echo "Node.js $(node --version)"'], note: launcher('node') },
  ts: { label: 'TypeScript', name: 'TypeScript (Node.js)', version: ['sh', '-c', 'echo "Node.js $(node --version), which runs .ts files natively"'], note: launcher('node') },
  python: { label: 'Python', name: 'Python 3', version: ['python3', '--version'], note: launcher('python3') },
  asm: {
    label: 'Assembly',
    name: 'AArch64 assembly for macOS',
    version: ['as', '--version'],
    note: 'Write all program logic in AArch64 assembly (.s files) assembled with clang. You may call libc / libSystem functions (malloc, read, write, socket, pthread…), but no C, C++ or other high-level source files.',
  },
}

// Quiet first-run banners that would cost every .NET run the same extra tokens.
process.env.DOTNET_CLI_TELEMETRY_OPTOUT = '1'
process.env.DOTNET_NOLOGO = '1'
// .NET build servers outlive the build and keep its stdout open, which hangs any caller waiting on it.
process.env.MSBUILDDISABLENODEREUSE = '1'
process.env.DOTNET_CLI_USE_MSBUILD_SERVER = '0'
process.env.UseSharedCompilation = 'false'

// Homebrew's OpenJDK is keg-only: put it on PATH for agents, builds and perf runs.
const JDK = '/opt/homebrew/opt/openjdk'
if (existsSync(JDK)) {
  process.env.JAVA_HOME ??= JDK
  process.env.PATH = `${JDK}/bin:${process.env.PATH}`
}

export const FRONTENDS = {
  react: { label: 'React', name: 'React 19 (function components + hooks, .jsx files)' },
  vue: { label: 'Vue', name: 'Vue 3 (single-file components with <script setup>, .vue files)' },
  svelte: { label: 'Svelte', name: 'Svelte 5 (components with runes, .svelte files)' },
}

export const TASKS = {
  wordfreq: { kind: 'stdio', title: 'Word frequency', topic: 'bytes, hash maps, sorting' },
  lru: { kind: 'stdio', title: 'LRU cache', topic: 'linked structures, O(1) ops' },
  calc: { kind: 'stdio', title: 'Expression evaluator', topic: 'parsing, recursion, overflow' },
  kvhttp: { kind: 'http', title: 'HTTP key-value server', topic: 'networking, concurrency, deps' },
  ui: { kind: 'static', title: 'Six UI components', topic: 'front end (React, Vue, Svelte)', frontend: true },
  shop: { kind: 'static', title: 'Shopping mini-app', topic: 'parent/child events, global store, derived state, forms, effects, context, slots', frontend: true },
}

const STDLIB_ONLY = 'Use only the standard library.'
const DEPS_OK =
  'Third-party packages are allowed if an experienced engineer would use them in production. Do not vendor them into this directory: build.sh must fetch them on a clean machine.'

export function prompt(task, lang, versionText) {
  if (TASKS[task].frontend) {
    const what = task === 'ui' ? 'the six components' : 'the app'
    return `Write ${what} specified in SPEC.md using ${FRONTENDS[lang].name}. Work only inside the current directory.\n\nWhen finished, reply with the single word DONE.`
  }
  const { name, note } = LANGS[lang]
  return `Implement the program specified in SPEC.md, in ${name}.

Environment: macOS arm64, toolchain: ${versionText}. Work only inside the current directory.

Requirements:
- Write idiomatic, production-quality ${LANGS[lang].label}: what an experienced ${LANGS[lang].label} engineer would write and maintain.
- ${task === 'kvhttp' ? DEPS_OK : STDLIB_ONLY}${note ? `\n- ${note}` : ''}
- Create build.sh: a bash script that, run from a clean copy of this directory, builds an optimized release binary and places it at ./app.
- Test with \`node check.mjs\` (runs build.sh, then the example cases in cases.json). Hidden tests check every rule in SPEC.md with more edge cases and larger inputs than the examples.
- Do not modify SPEC.md, check.mjs or cases.json.${task === 'kvhttp' ? '\n- Other runs share this machine: if you start the server by hand, use a random port between 20000 and 60000.' : ''}

When finished, reply with the single word DONE.`
}

export const runDir = (lang, task, rep) => join(RUNS, lang, task, `r${rep}`)
export const runId = (lang, task, rep) => `${lang}-${task}-r${rep}`

// Round 4: a fresh agent gets the project that failed round 3 plus the failure report.
export function repairPrompt(task, lang, versionText, report) {
  if (TASKS[task].frontend) {
    return `The ${FRONTENDS[lang].name} code in this directory implements SPEC.md, but it failed acceptance testing. The test builds it with Vite, imports each component file by name, mounts it with the props from SPEC.md and exercises it in a browser.

Failure report:
${report}

Fix the code. The rules of SPEC.md still apply: plain JavaScript, one component per file named after the component, no build setup, no package.json, no tests. Work only inside the current directory.

When finished, reply with the single word DONE.`
  }
  const { name, label, note } = LANGS[lang]
  return `The program in this directory implements SPEC.md in ${name}, but it failed acceptance testing.

Failure report:
${report}

Fix it. Environment: macOS arm64, toolchain: ${versionText}. Work only inside the current directory.
- Keep it idiomatic, production-quality ${label}. ${task === 'kvhttp' ? DEPS_OK : STDLIB_ONLY}${note ? `\n- ${note}` : ''}
- build.sh must still build an optimized release binary at ./app from a clean copy of this directory.
- \`node check.mjs\` runs the example cases; the acceptance suite has more cases than the examples.
- Do not modify SPEC.md, check.mjs or cases.json.

When finished, reply with the single word DONE.`
}
