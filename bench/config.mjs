// Single source of truth for what the benchmark runs.
import { existsSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

export const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')

// Experimental arm. base: the published run, no rules of any kind. skills: the same run plus one
// project Skill per language (bench/skills/<lang>/SKILL.md), offered through the Skill tool.
export const ARM = process.env.TKN_ARM ?? 'base'
if (!['base', 'skills'].includes(ARM)) throw new Error(`unknown TKN_ARM "${ARM}" (base, skills)`)
const armSuffix = ARM === 'base' ? '' : `-${ARM}`
export const BASE_RUNS = join(ROOT, 'runs')
export const RUNS = join(ROOT, `runs${armSuffix}`)
export const WORK = process.env.TKN_WORK ?? join(tmpdir(), `tknbench${armSuffix}`)
export const SKILLS = join(ROOT, 'bench', 'skills')
// Claude Code binary. Arms other than base must match the baseline's version (run.mjs checks).
export const CLAUDE_BIN = process.env.TKN_CLAUDE ?? 'claude'

export const MODEL = 'claude-opus-5-5'
export const EFFORT = 'high'
export const TOOLS = 'Bash,Read,Edit,Write'
export const RUN_TIMEOUT_MS = 30 * 60 * 1000

// Agent CLI per arm. skills adds the Skill tool and hides every skill but the language's own:
// bundled skills off, plus the three that survive that switch in Claude Code 2.1.331, by name.
const SKILL_ONLY = { skillOverrides: { design: 'off', doctor: 'off', 'plugin-authoring': 'off' } }
export const AGENT_CLI =
  ARM === 'skills'
    ? { tools: `${TOOLS},Skill`, args: ['--settings', JSON.stringify(SKILL_ONLY)], env: { CLAUDE_CODE_DISABLE_BUNDLED_SKILLS: '1' } }
    : { tools: TOOLS, args: [], env: {} }

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

// Specialised tracks: own languages and tasks, ranked separately from the main track.
export const TRACKS = {
  numeric: { title: 'Scientific computing', tasks: ['linreg', 'linalg'] },
  proofs: { title: 'Theorem proving', tasks: ['lists', 'isort'] },
  evm: { title: 'Smart contracts', tasks: ['token', 'vesting'] },
  zk: { title: 'Zero-knowledge circuits', tasks: ['range', 'sudoku'] },
}

Object.assign(LANGS, {
  octave: { label: 'Octave', name: 'GNU Octave (the MATLAB language)', version: ['sh', '-c', 'octave --version | head -1'], note: launcher('octave'), track: 'numeric' },
  julia: { label: 'Julia', name: 'Julia', version: ['julia', '--version'], note: launcher('julia'), track: 'numeric' },
  r: { label: 'R', name: 'R', version: ['sh', '-c', 'R --version | head -1'], note: launcher('Rscript'), track: 'numeric' },
  lean: { label: 'Lean 4', name: 'Lean 4', version: ['lean', '--version'], track: 'proofs' },
  rocq: { label: 'Rocq', name: 'Rocq (Coq)', version: ['sh', '-c', 'coqc --version | head -1'], track: 'proofs' },
  dafny: { label: 'Dafny', name: 'Dafny', version: ['sh', '-c', 'echo "Dafny $(dafny --version)"'], track: 'proofs' },
  solidity: { label: 'Solidity', name: 'Solidity (Foundry is installed)', version: ['sh', '-c', 'forge --version | head -1'], track: 'evm' },
  vyper: { label: 'Vyper', name: 'Vyper', version: ['sh', '-c', 'echo "Vyper $(vyper --version)"'], track: 'evm' },
  circom: { label: 'Circom', name: 'Circom 2', version: ['circom', '--version'], track: 'zk' },
  noir: { label: 'Noir', name: 'Noir (nargo)', version: ['sh', '-c', 'nargo --version | head -1'], track: 'zk' },
})
export const MAIN_LANGS = Object.keys(LANGS).filter((k) => !LANGS[k].track)
export const trackLangs = (track) => Object.keys(LANGS).filter((k) => LANGS[k].track === track)

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

// pins: the packages the front-end verifier builds with, at the versions of the published run.
export const FRONTENDS = {
  react: { label: 'React', name: 'React 19 (function components + hooks, .jsx files)', pins: { react: '19.3.1', 'react-dom': '19.3.1', vite: '8.3.8', '@vitejs/plugin-react': '6.3.0' } },
  vue: { label: 'Vue', name: 'Vue 3 (single-file components with <script setup>, .vue files)', pins: { vue: '3.5.46', vite: '8.3.8', '@vitejs/plugin-vue': '6.0.11', pinia: '4.1.0' } },
  svelte: { label: 'Svelte', name: 'Svelte 5 (components with runes, .svelte files)', pins: { svelte: '5.59.1', vite: '8.3.8', '@sveltejs/vite-plugin-svelte': '7.3.2' } },
}

export const TASKS = {
  wordfreq: { kind: 'stdio', title: 'Word frequency', topic: 'bytes, hash maps, sorting' },
  lru: { kind: 'stdio', title: 'LRU cache', topic: 'linked structures, O(1) ops' },
  calc: { kind: 'stdio', title: 'Expression evaluator', topic: 'parsing, recursion, overflow' },
  kvhttp: { kind: 'http', title: 'HTTP key-value server', topic: 'networking, concurrency, deps' },
  ui: { kind: 'static', title: 'Six UI components', topic: 'front end (React, Vue, Svelte)', frontend: true },
  shop: { kind: 'static', title: 'Shopping mini-app', topic: 'parent/child events, global store, derived state, forms, effects, context, slots', frontend: true },
  linreg: { kind: 'stdio', title: 'Least-squares regression', topic: 'numerics, matrices', track: 'numeric' },
  linalg: { kind: 'stdio', title: 'Linear algebra', topic: 'log-determinant, solve, eigenvalues', track: 'numeric' },
  lists: { kind: 'proof', title: 'List lemmas', topic: 'induction, rewriting', track: 'proofs' },
  isort: { kind: 'proof', title: 'Insertion sort is correct', topic: 'sortedness, permutation', track: 'proofs' },
  token: { kind: 'evm', title: 'Token with allowances', topic: 'storage, events, reverts', track: 'evm' },
  vesting: { kind: 'evm', title: 'Linear vesting', topic: 'time, ether transfers', track: 'evm' },
  range: { kind: 'zk', title: 'Private range check', topic: 'bit decomposition, comparisons', track: 'zk' },
  sudoku: { kind: 'zk', title: '4x4 Sudoku', topic: 'permutation constraints', track: 'zk' },
}

const TRACK_CONTRACT = {
  proofs: [
    '- Complete every proof in the file(s) provided with SPEC.md. Do not change any definition or theorem statement, and do not add axioms or escape hatches (sorry, admit, Admitted, assume, {:axiom}).',
    '- Use only the standard library of the language (no Mathlib or other packages).',
    '- Create build.sh: a bash script that, run from a clean copy of this directory, checks all proofs and exits 0 only if every proof is accepted.',
  ],
  evm: [
    '- Third-party libraries are allowed if an experienced engineer would use them in production. Do not vendor them into this directory: build.sh must fetch them on a clean machine.',
    '- Create build.sh: a bash script that, run from a clean copy of this directory, compiles the contract and writes out/<ContractName>.json containing {"abi": [...], "bytecode": "0x..."} (creation bytecode), using the contract name given in SPEC.md.',
  ],
  zk: [
    '- Third-party libraries are allowed if an experienced engineer would use them in production. Do not vendor them into this directory: build.sh must fetch them on a clean machine.',
    '- Create build.sh: a bash script that, run from a clean copy of this directory, compiles the circuit.',
    '- Create prove.sh: `bash prove.sh input.json` must exit 0 if the inputs satisfy the circuit (a witness can be generated, or the program executes without a failed assertion) and non-zero otherwise.',
  ],
}

const TRACK_GOAL = {
  proofs: 'Complete the proofs specified in SPEC.md',
  evm: 'Implement the smart contract specified in SPEC.md',
  zk: 'Implement the circuit specified in SPEC.md',
}

function trackPrompt(lang, versionText) {
  const { name, label, track } = LANGS[lang]
  return `${TRACK_GOAL[track]}, in ${name}.

Environment: macOS arm64, toolchain: ${versionText}. Work only inside the current directory.

Requirements:
- Write idiomatic, production-quality ${label}: what an experienced ${label} engineer would write and maintain.
${TRACK_CONTRACT[track].join('\n')}
- Test with \`node check.mjs\` (runs build.sh, then the example cases in cases.json). Hidden tests check every rule in SPEC.md.
- Do not modify SPEC.md, check.mjs or cases.json.

When finished, reply with the single word DONE.`
}

const STDLIB_ONLY = 'Use only the standard library.'
const DEPS_OK =
  'Third-party packages are allowed if an experienced engineer would use them in production. Do not vendor them into this directory: build.sh must fetch them on a clean machine.'

export function prompt(task, lang, versionText) {
  if (TRACK_CONTRACT[TASKS[task].track]) return trackPrompt(lang, versionText)
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

// Skills arm: one agent per language writes the skill. Same text for every language, filled with the
// installed version; it never mentions the benchmark or its tasks.
export const SKILL_MAX_BYTES = 8000

export function skillPrompt(lang, versionText) {
  const { label, name } = LANGS[lang] ?? FRONTENDS[lang]
  return `Write a Claude Code skill for ${name}: the reference an expert would hand an AI coding agent so that it writes correct, idiomatic, production-quality ${label} for exactly this version on the first try.

Environment: macOS arm64. Installed: ${versionText}. Web search and web fetch are available. Work only inside the current directory.

Work in three phases, in this order.

1. Research what is actually used, before writing anything. Find and read:
   - the official documentation and release notes for this exact version, and the breaking changes of recent releases (APIs renamed, moved or removed);
   - the official or most widely followed style guide;
   - agent skills, CLAUDE.md, AGENTS.md or editor rules that experienced ${label} developers have published, and what they agree on;
   - how experienced engineers set up, build, test and ship a small ${label} project today, and the standard-library or core APIs they use day to day in this version.
   Record every source you used in SOURCES.md: its URL and one line on what you took from it.
2. Verify against the installed toolchain. Do not trust memory or the web for version-specific details: check every API name, signature, import path, command and flag you plan to include, in the installed sources or by building and running a small snippet in a scratch directory. Drop or correct anything that fails.
3. Write SKILL.md: the skill body only (no YAML front matter), in Markdown, at most ${SKILL_MAX_BYTES} bytes. Spend the space on what an agent gets wrong without it: version-specific API with short verified examples, build and release commands, project layout, idioms that are both correct and fast, and common compiler or runtime errors with their fixes. Skip generic advice any ${label} developer already knows.

Rules:
- The skill is general-purpose: it must help with any ${label} program, not one particular project.
- Do not use or cite material about LLM benchmarks or token-cost comparisons between programming languages.
- Delete scratch files when done; leave only SKILL.md and SOURCES.md.

When finished, reply with the single word DONE.`
}
