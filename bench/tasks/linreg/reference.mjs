import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'

// Solves the SPD system M z = v by Cholesky decomposition.
export function choleskySolve(m, v) {
  const n = m.length
  const l = Array.from({ length: n }, () => new Float64Array(n))
  for (let i = 0; i < n; i++) {
    for (let j = 0; j <= i; j++) {
      let sum = m[i][j]
      for (let p = 0; p < j; p++) sum -= l[i][p] * l[j][p]
      l[i][j] = i === j ? Math.sqrt(sum) : sum / l[j][j]
    }
  }
  const y = new Float64Array(n)
  for (let i = 0; i < n; i++) y[i] = (v[i] - l[i].slice(0, i).reduce((s, x, p) => s + x * y[p], 0)) / l[i][i]
  const z = new Float64Array(n)
  for (let i = n - 1; i >= 0; i--) {
    let sum = y[i]
    for (let p = i + 1; p < n; p++) sum -= l[p][i] * z[p]
    z[i] = sum / l[i][i]
  }
  return { z, l }
}

export function solve(buf) {
  const nums = buf.toString().trim().split(/\s+/).map(Number)
  const [n, k] = nums
  const d = k + 1
  const xtx = Array.from({ length: d }, () => new Float64Array(d))
  const xty = new Float64Array(d)
  const rows = []
  for (let i = 0; i < n; i++) {
    const row = [1, ...nums.slice(2 + i * d, 2 + i * d + k)]
    const y = nums[2 + i * d + k]
    rows.push([row, y])
    for (let a = 0; a < d; a++) {
      xty[a] += row[a] * y
      for (let b = 0; b < d; b++) xtx[a][b] += row[a] * row[b]
    }
  }
  const { z: beta } = choleskySolve(xtx, xty)
  const mean = rows.reduce((s, [, y]) => s + y, 0) / n
  let ssRes = 0
  let ssTot = 0
  for (const [row, y] of rows) {
    const fit = row.reduce((s, x, a) => s + x * beta[a], 0)
    ssRes += (y - fit) ** 2
    ssTot += (y - mean) ** 2
  }
  return [...beta, 1 - ssRes / ssTot].map((v) => v.toPrecision(15)).join('\n')
}

if (process.argv[1] === fileURLToPath(import.meta.url)) process.stdout.write(solve(readFileSync(0)) + '\n')
