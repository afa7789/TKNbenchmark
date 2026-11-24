// Turns a `claude -p --output-format stream-json` transcript into per-run metrics.

// Commands that invoke a compiler or the checker (reading or writing those files does not count).
const BUILD_RE = /\b(cargo (build|run|test|check)|go (build|run|vet|test)|zig (build|build-exe|run|test)|nim (c|cpp|compile)|nimble (build|install)|clang\+\+ |g\+\+ |c\+\+ |cmake (--build|-S|-B)|make\b|(bash|sh) (\.\/)?build\.sh|\.\/build\.sh|node (\S*\/)?check\.mjs)/
const CHECK_RE = /node (\S*\/)?check\.mjs/
const HEREDOC_RE = /<<-?\s*['"]?(\w+)['"]?[\s\S]*?\n\1\b/g
// Compiler diagnostics in tool output (exit codes hide behind pipes like `2>&1 | tail`).
const COMPILER_ERR_RE = /(:\d+:\d+: error:|^error(\[E\d+\])?: |\.nim\(\d+, \d+\) Error:|^# \S+\n\S+\.go:\d+:\d+: |^BUILD FAIL)/m
// Reading the toolchain's own library sources or docs to learn an API.
const STDLIB_RE = /(lib\/zig\/std|zig env|rustlib\/src|\.cargo\/registry|go doc|libexec\/src|GOROOT|nim\/lib|lib\/pure|lib\/std\/|include\/c\+\+|\/usr\/include|SDKs?\/MacOSX|Cellar\/[\w.-]+\/[\w.-]+\/(lib|libexec|share|include|src)|lib\/ocaml|\.opam\/|ocamlfind (list|query)|\.cabal\/packages|ghc-pkg|\.nuget\/packages|javap|swiftinterface|\.swiftmodule|Toolchains\/)/
const RESULT_RE = /RESULT pass=(\d+) total=(\d+)( build=fail)?/

function resultText(block) {
  if (typeof block.content === 'string') return block.content
  return (block.content ?? []).map((c) => c.text ?? '').join('\n')
}

function classify(cmd, block) {
  const text = resultText(block)
  const isCheck = CHECK_RE.test(cmd)
  const m = text.match(RESULT_RE)
  const compileError = COMPILER_ERR_RE.test(text)
  return { isCheck, compileError, check: isCheck && m ? { pass: Number(m[1]), total: Number(m[2]) } : null }
}

const bashCommand = (use) => (use?.name === 'Bash' ? String(use.input?.command ?? '').replace(HEREDOC_RE, '') : '')

const touchesStdlib = (use) => STDLIB_RE.test(String(use?.input?.command ?? use?.input?.file_path ?? ''))

function onResult(m, block, use) {
  if (block.is_error) m.toolErrors++
  if (touchesStdlib(use)) m.stdlibReads++
  const cmd = bashCommand(use)
  if (!BUILD_RE.test(cmd)) return
  const c = classify(cmd, block)
  m.builds++
  if (c.compileError) m.compileErrors++
  if (c.check) m.checks.push(c.check)
}

function tally(events) {
  const uses = new Map()
  const tools = {}
  const m = { builds: 0, compileErrors: 0, checks: [], toolErrors: 0, stdlibReads: 0 }
  for (const ev of events) {
    for (const b of ev.message?.content ?? []) {
      if (b.type === 'tool_use') {
        uses.set(b.id, b)
        tools[b.name] = (tools[b.name] ?? 0) + 1
      } else if (b.type === 'tool_result') onResult(m, b, uses.get(b.tool_use_id))
    }
  }
  return { ...m, tools }
}

// Fallback when the run was killed before the final `result` event.
function sumUsage(events) {
  const byId = new Map()
  for (const ev of events) if (ev.type === 'assistant' && ev.message?.usage) byId.set(ev.message.id, ev.message.usage)
  const u = { input_tokens: 0, output_tokens: 0, cache_read_input_tokens: 0, cache_creation_input_tokens: 0 }
  for (const x of byId.values()) for (const k of Object.keys(u)) u[k] += x[k] ?? 0
  return u
}

function runFields(r) {
  if (!r) return { finished: false, terminalReason: 'killed', costUsd: null, durationMs: null, apiMs: null, turns: null, models: [], reply: '' }
  return {
    finished: !r.is_error,
    terminalReason: r.terminal_reason,
    costUsd: r.total_cost_usd,
    durationMs: r.duration_ms,
    apiMs: r.duration_api_ms,
    turns: r.num_turns,
    models: Object.keys(r.modelUsage ?? {}),
    reply: String(r.result ?? '').slice(0, 500),
  }
}

const usageFields = (u) => ({
  input: u.input_tokens,
  output: u.output_tokens,
  thinking: u.output_tokens_details?.thinking_tokens ?? null,
  cacheRead: u.cache_read_input_tokens,
  cacheWrite: u.cache_creation_input_tokens,
})

export function parseTranscript(text) {
  const events = text
    .split('\n')
    .filter(Boolean)
    .map((l) => JSON.parse(l))
  const result = events.find((e) => e.type === 'result')
  const t = tally(events)
  const first = t.checks[0]
  return {
    ...runFields(result),
    usage: usageFields(result?.usage ?? sumUsage(events)),
    tools: t.tools,
    toolErrors: t.toolErrors,
    stdlibReads: t.stdlibReads,
    builds: t.builds,
    compileErrors: t.compileErrors,
    checkRuns: t.checks.length,
    checkFails: t.checks.filter((c) => c.pass < c.total).length,
    firstCheckPass: Boolean(first) && first.pass === first.total,
    lastCheck: t.checks.at(-1) ?? null,
  }
}
