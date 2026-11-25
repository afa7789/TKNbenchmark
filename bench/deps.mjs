// Third-party dependencies a solution declares, read from its build manifests.
const words = (s) => s.split(/[\s,]+/).filter(Boolean)
const all = (text, re, group = 1) => [...text.matchAll(re)].map((m) => m[group])

function cargo(text) {
  const block = text.match(/\[dependencies\]([\s\S]*?)(\n\[|$)/)?.[1] ?? ''
  return all(block, /^([\w-]+)\s*=/gm)
}

function goMod(text) {
  const block = text.match(/require\s*\(([\s\S]*?)\)/)?.[1] ?? text.match(/require\s+(\S+)/)?.[1] ?? ''
  return all(block, /^\s*(\S+)\s+v\S+(?!.*indirect)/gm).map((p) => p.split('/').slice(-2).join('/'))
}

function nimble(text) {
  return all(text, /requires\s+(.+)/g).flatMap((line) => all(line, /"([\w-]+)/g)).filter((n) => n !== 'nim')
}

function cabal(text) {
  const blocks = all(text, /build-depends:\s*([\s\S]*?)(?=\n\s*[\w-]+:|\n\S|$)/g)
  return blocks.flatMap((b) => b.split(',').map((d) => words(d)[0])).filter((n) => n && n !== 'base')
}

function packageJson(text) {
  try {
    return Object.keys(JSON.parse(text).dependencies ?? {})
  } catch {
    return []
  }
}

const pyRequirements = (t) => all(t, /^\s*([A-Za-z0-9_.-]+)\s*(?:[<>=~!;[]|$)/gm)
const pyProject = (t) => all(t.match(/dependencies\s*=\s*\[([\s\S]*?)\]/)?.[1] ?? '', /["']([A-Za-z0-9_.-]+)/g)

const DUNE_STDLIB = new Set(['unix', 'threads', 'threads.posix', 'str'])
// deps.edn coordinates (lib {:mvn/version …} / {:git/…} / {:local/…}), minus Clojure itself and tools.build.
const CLJ_TOOLING = new Set(['clojure', 'tools.build'])
const depsEdn = (t) => all(t, /([\w.-]+\/)?([\w.-]+)\s*\{\s*:(?:mvn|git|local)\//g, 2).filter((n) => !CLJ_TOOLING.has(n))

const MANIFESTS = [
  [/^Cargo\.toml$/, cargo],
  [/^go\.mod$/, goMod],
  [/^build\.zig\.zon$/, (t) => all(t, /\.([\w-]+)\s*=\s*\.\{\s*\.url/g)],
  [/^Package\.swift$/, (t) => all(t, /\.package\(\s*url:\s*"[^"]*\/([^/"]+?)(?:\.git)?"/g)],
  [/^pom\.xml$/, (t) => all(t, /<dependency>[\s\S]*?<artifactId>([^<]+)<\/artifactId>/g)],
  [/^build\.gradle(\.kts)?$/, (t) => all(t, /(?:implementation|api)\s*\(?\s*["'][^"':]+:([^"':]+)/g)],
  [/\.nimble$/, nimble],
  [/^CMakeLists\.txt$/, (t) => all(t, /FetchContent_Declare\(\s*(\w+)/g)],
  [/\.csproj$/, (t) => all(t, /PackageReference\s+Include="([^"]+)"/g)],
  [/^dune$/, (t) => all(t, /\(libraries\s+([^)]+)\)/g).flatMap(words).filter((n) => !DUNE_STDLIB.has(n))],
  [/\.cabal$|^package\.yaml$/, cabal],
  [/^package\.json$/, packageJson],
  [/^requirements\.txt$/, pyRequirements],
  [/^pyproject\.toml$/, pyProject],
  [/^deps\.edn$/, depsEdn],
]

// Libraries a dune project declares itself, so (libraries kvhttp) is not mistaken for a package.
const duneLocal = (files) => new Set(files.filter((f) => f.path.endsWith('dune')).flatMap((f) => all(f.text, /\(library[\s\S]*?\(name\s+([\w-]+)\)/g)))

// files: [{ path, text }]
export function detectDeps(files) {
  const local = duneLocal(files)
  const found = new Set()
  for (const { path, text } of files) {
    const name = path.split('/').at(-1)
    for (const [re, parse] of MANIFESTS) if (re.test(name)) parse(text).forEach((d) => !local.has(d) && found.add(d))
  }
  return [...found].sort()
}
