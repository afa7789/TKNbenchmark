// Round 3 (front end): build each solution with Vite and smoke-test it in headless Chromium.
// Checks use only what the SPEC states literally (texts, buttons named Add/Remove, props), plus
// "no runtime errors". Network calls are mocked. node bench/verify-front.mjs [--force]
import { spawnSync } from 'node:child_process'
import { existsSync, mkdirSync, readFileSync, readdirSync, rmSync, symlinkSync, writeFileSync } from 'node:fs'
import http from 'node:http'
import { extname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { chromium } from 'playwright'
import { FRONTENDS, RUNS, WORK } from './config.mjs'
import { copyFiles, parseArgs, readJson, solutionFiles, writeJson } from './lib.mjs'

const deps = (fw) => Object.keys(FRONTENDS[fw].pins)
const FW = {
  react: { deps: deps('react'), plugin: ["import react from '@vitejs/plugin-react'", 'react()'], exts: ['.jsx', '.js'] },
  vue: { deps: deps('vue'), plugin: ["import vue from '@vitejs/plugin-vue'", 'vue()'], exts: ['.vue'] },
  svelte: { deps: deps('svelte'), plugin: ["import { svelte } from '@sveltejs/vite-plugin-svelte'", 'svelte()'], exts: ['.svelte'] },
}
// Framework and build packages at pinned versions (every arm builds with the same ones); extra
// packages an agent imported install at their latest.
const PINS = Object.assign({}, ...Object.values(FRONTENDS).map((f) => f.pins))
const pinned = (d) => (PINS[d] ? `${d}@${PINS[d]}` : d)

const MOUNT = {
  react: () => "import { createElement } from 'react'\nimport { createRoot } from 'react-dom/client'\nexport const mountOne = (C, el, props) => createRoot(el).render(createElement(C, props))\n",
  vue: (pinia) =>
    `import { createApp } from 'vue'\n${pinia ? "import { createPinia } from 'pinia'\n" : ''}export function mountOne(C, el, props) {\n  const app = createApp(C, props)\n${pinia ? '  app.use(createPinia())\n' : ''}  app.mount(el)\n}\n`,
  svelte: () => "import { mount } from 'svelte'\nexport const mountOne = (C, el, props) => mount(C, { target: el, props })\n",
}

const ROWS = [{ name: 'Apple', price: 2, qty: 3 }, { name: 'banana', price: 1, qty: 5 }, { name: 'Cherry', price: 10, qty: 1 }]
const PRODUCTS = [{ id: 1, name: 'Keyboard', price: 50, category: 'tech' }, { id: 2, name: 'Mouse', price: 20, category: 'tech' }, { id: 3, name: 'Coffee', price: 8, category: 'food' }]
const USERS = [{ id: 1, name: 'Leanne Graham' }, { id: 2, name: 'Ervin Howell' }]

const PLANS = {
  ui: [['Hello', { name: 'Ada' }], ['Counter', {}], ['Todo', {}], ['FetchUsers', {}], ['FilterTable', { rows: ROWS }], ['KvBrowser', { baseUrl: 'http://kv.test' }]],
  shop: [['App', { products: PRODUCTS }]],
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms))

async function waitText(locator, pred, ms = 3000) {
  const end = Date.now() + ms
  while (Date.now() < end) {
    if (pred(await locator.innerText().catch(() => ''))) return true
    await sleep(100)
  }
  return false
}

const has = (...words) => (t) => words.every((w) => t.includes(w))
const count = (t, w) => t.split(w).length - 1

const CHECKS = {
  ui: {
    hello: (p) => waitText(p.locator('#c-Hello'), has('Hello, Ada!')),
    counter: async (p) => {
      const box = p.locator('#c-Counter')
      const before = await box.innerText()
      await box.locator('button').first().click()
      return waitText(box, (t) => t !== before && /(^|\D)1(\D|$)/.test(t))
    },
    todo: async (p) => {
      const box = p.locator('#c-Todo')
      await box.locator('input').first().fill('Buy milk')
      await box.getByRole('button', { name: /add/i }).first().click()
      if (!(await waitText(box, has('Buy milk')))) return false
      await box.getByRole('button', { name: /remove/i }).first().click()
      return waitText(box, (t) => !t.includes('Buy milk'))
    },
    'fetch-users': (p) => waitText(p.locator('#c-FetchUsers'), has('Leanne Graham', 'Ervin Howell')),
    'filter-table': async (p) => {
      const box = p.locator('#c-FilterTable')
      if (!(await waitText(box, has('Apple', 'banana', 'Cherry', '21')))) return false
      await box.locator('input').first().fill('an')
      return waitText(box, (t) => t.includes('banana') && !t.includes('Cherry') && !t.includes('Apple'))
    },
    'kv-browser': (p) => waitText(p.locator('#c-KvBrowser'), has('alpha', 'beta')),
  },
  shop: {
    products: (p) => waitText(p.locator('body'), has('Keyboard', 'Mouse', 'Coffee')),
    'add-to-cart': async (p) => {
      const body = p.locator('body')
      const before = count(await body.innerText(), 'Keyboard')
      await p.getByRole('button', { name: /add/i }).first().click()
      return waitText(body, (t) => count(t, 'Keyboard') > before)
    },
    'debounced-search': async (p) => {
      await p.locator('input[type="search"], input[type="text"], input:not([type])').first().fill('Cof')
      return waitText(p.locator('body'), (t) => t.includes('Coffee') && !t.includes('Mouse'), 3000)
    },
  },
}

// ---------- build ----------

function ensureBase(fw, extra = []) {
  const base = join(WORK, 'front-base', fw)
  const want = [...FW[fw].deps, ...extra].filter((d) => !existsSync(join(base, 'node_modules', d, 'package.json')))
  if (!want.length) return base
  mkdirSync(base, { recursive: true })
  if (!existsSync(join(base, 'package.json'))) writeFileSync(join(base, 'package.json'), '{ "private": true, "type": "module" }\n')
  const r = spawnSync('npm', ['install', '--silent', '--no-audit', '--no-fund', ...want.map(pinned)], { cwd: base, encoding: 'utf8' })
  if (r.status !== 0) console.error(`npm install ${want.join(' ')} failed: ${r.stderr.slice(-500)}`)
  return base
}

const pkgName = (spec) => (spec.startsWith('@') ? spec.split('/').slice(0, 2).join('/') : spec.split('/')[0])

function bareImports(dir, files) {
  const out = new Set()
  for (const f of files) {
    for (const m of readFileSync(join(dir, f), 'utf8').matchAll(/(?:from|import)\s*\(?\s*['"]([^'"./][^'"]*)['"]/g)) out.add(pkgName(m[1]))
  }
  return [...out]
}

function findComponent(files, name, exts) {
  return files.find((f) => exts.includes(extname(f)) && f.split('/').at(-1).replace(/\.[^.]+$/, '') === name)
}

function writeEntry(dir, fw, task, files, usesPinia) {
  const plan = PLANS[task].map(([name, props]) => ({ name, props, file: findComponent(files, name, FW[fw].exts) }))
  const found = plan.filter((x) => x.file)
  const imports = found.map((x, i) => `import * as M${i} from './src/${x.file}'`).join('\n')
  const mounts = found.map((x, i) => `  ['${x.name}', M${i}.default ?? M${i}.${x.name}, ${JSON.stringify(x.props)}],`).join('\n')
  writeFileSync(join(dir, 'mount.js'), MOUNT[fw](usesPinia))
  writeFileSync(
    join(dir, 'main.js'),
    `import { mountOne } from './mount.js'\n${imports}\nfor (const [name, C, props] of [\n${mounts}\n]) {\n  const el = document.createElement('div')\n  el.id = 'c-' + name\n  document.body.append(el)\n  try { mountOne(C, el, props) } catch (e) { console.error('mount ' + name + ': ' + e.message) }\n}\n`,
  )
  writeFileSync(join(dir, 'index.html'), '<!doctype html>\n<html><head><meta charset="utf-8"></head><body><script type="module" src="/main.js"></script></body></html>\n')
  const [imp, call] = FW[fw].plugin
  writeFileSync(join(dir, 'vite.config.mjs'), `import { defineConfig } from 'vite'\n${imp}\nexport default defineConfig({ plugins: [${call}], logLevel: 'error', build: { minify: false } })\n`)
  return plan.filter((x) => !x.file).map((x) => x.name)
}

function build(solDir, fw, task, id) {
  const dir = join(WORK, 'front', id)
  rmSync(dir, { recursive: true, force: true })
  const files = solutionFiles(solDir)
  copyFiles(solDir, join(dir, 'src'), files)
  const frameworkPkgs = new Set([...FW[fw].deps, 'svelte'])
  const extra = bareImports(solDir, files).filter((p) => !frameworkPkgs.has(p))
  const base = ensureBase(fw, extra)
  symlinkSync(join(base, 'node_modules'), join(dir, 'node_modules'))
  const missing = writeEntry(dir, fw, task, files, extra.includes('pinia') || bareImports(solDir, files).includes('pinia'))
  const t0 = performance.now()
  const r = spawnSync('node', [join(base, 'node_modules', 'vite', 'bin', 'vite.js'), 'build'], { cwd: dir, encoding: 'utf8', timeout: 120_000 })
  const buildSecs = Number(((performance.now() - t0) / 1000).toFixed(2))
  return { dir, missing, buildSecs, buildOk: r.status === 0, buildLog: r.status === 0 ? '' : `${r.stdout}${r.stderr}`.slice(-3000), extra }
}

// ---------- browser ----------

function serve(root) {
  const types = { '.js': 'text/javascript', '.css': 'text/css', '.html': 'text/html' }
  const srv = http.createServer((req, res) => {
    const path = join(root, req.url === '/' ? 'index.html' : req.url.split('?')[0])
    if (!existsSync(path)) return res.writeHead(req.url === '/favicon.ico' ? 204 : 404).end()
    res.writeHead(200, { 'Content-Type': types[extname(path)] ?? 'application/octet-stream' }).end(readFileSync(path))
  })
  return new Promise((resolve) => srv.listen(0, '127.0.0.1', () => resolve(srv)))
}

const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Methods': 'GET,PUT,DELETE,OPTIONS', 'Access-Control-Allow-Headers': '*' }

function kvMock(store) {
  return async (route) => {
    const req = route.request()
    const key = decodeURIComponent(new URL(req.url()).pathname.replace(/^\/kv\/?/, ''))
    const method = req.method()
    const reply = (status, body = '', type = 'text/plain') => route.fulfill({ status, body, headers: { ...CORS, 'Content-Type': type } })
    if (method === 'OPTIONS') return reply(204)
    if (!key) return reply(200, JSON.stringify([...store.keys()].sort()), 'application/json')
    if (method === 'PUT') {
      const status = store.has(key) ? 200 : 201
      store.set(key, req.postData() ?? '')
      return reply(status)
    }
    if (method === 'DELETE') return reply(store.delete(key) ? 204 : 404)
    return store.has(key) ? reply(200, store.get(key)) : reply(404)
  }
}

async function runCheck(page, name, check) {
  try {
    if (await check(page)) return { name, ok: true }
    return { name, ok: false, why: `${name}: expected behaviour not observed` }
  } catch (e) {
    return { name, ok: false, why: `${name}: ${e.message.split('\n')[0]}` }
  }
}

async function smoke(dir, task) {
  const srv = await serve(join(dir, 'dist'))
  const browser = await chromium.launch()
  const page = await browser.newPage()
  page.setDefaultTimeout(3000)
  const errors = []
  page.on('pageerror', (e) => errors.push(String(e.message)))
  page.on('console', (m) => m.type() === 'error' && errors.push(m.text()))
  await page.route('https://jsonplaceholder.typicode.com/**', (r) => r.fulfill({ json: USERS, headers: CORS }))
  await page.route('http://kv.test/**', kvMock(new Map([['alpha', '1'], ['beta', '2']])))
  try {
    await page.goto(`http://127.0.0.1:${srv.address().port}/`)
    await sleep(800)
    const cases = []
    for (const [name, check] of Object.entries(CHECKS[task])) cases.push(await runCheck(page, name, check))
    cases.push({ name: 'no-runtime-errors', ok: errors.length === 0, why: errors.length ? errors.slice(0, 5).join(' | ').slice(0, 400) : undefined })
    return cases
  } finally {
    await browser.close()
    srv.close()
  }
}

export async function verifyFront(solDir, fw, task, id) {
  const b = build(solDir, fw, task, id)
  const total = Object.keys(CHECKS[task]).length + 2
  const buildCase = { name: 'vite-build', ok: b.buildOk && !b.missing.length, why: b.missing.length ? `missing component files: ${b.missing.join(', ')}` : b.buildOk ? undefined : b.buildLog.slice(-400) }
  const cases = b.buildOk ? [buildCase, ...(await smoke(b.dir, task))] : [buildCase]
  const pass = cases.filter((c) => c.ok).length
  rmSync(b.dir, { recursive: true, force: true })
  console.log(`${id}: build=${b.buildOk} ${b.buildSecs}s smoke=${pass}/${total}${b.extra.length ? ` deps=${b.extra.join(',')}` : ''}`)
  return { buildOk: b.buildOk, buildSecs: b.buildSecs, buildLog: b.buildLog, deps: b.extra, pass, total, solved: pass === total, cases }
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const args = parseArgs(process.argv.slice(2), {})
  for (const fw of Object.keys(FW)) {
    for (const task of Object.keys(PLANS)) {
      const dir = join(RUNS, fw, task)
      if (!existsSync(dir)) continue
      for (const rep of readdirSync(dir)) {
        const run = join(dir, rep)
        if (!existsSync(join(run, 'agent.json')) || (existsSync(join(run, 'verify.json')) && !args.force)) continue
        const meta = readJson(join(run, 'agent.json'))
        writeJson(join(run, 'verify.json'), await verifyFront(join(run, 'solution'), fw, task, meta.id))
      }
    }
  }
}
