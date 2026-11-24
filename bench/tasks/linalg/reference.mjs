import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { choleskySolve } from '../linreg/reference.mjs'

// Cyclic Jacobi eigenvalue algorithm for a symmetric matrix.
function rotate(a, p, q) {
  const n = a.length
  const theta = (a[q][q] - a[p][p]) / (2 * a[p][q])
  const t = Math.sign(theta || 1) / (Math.abs(theta) + Math.sqrt(theta * theta + 1))
  const c = 1 / Math.sqrt(t * t + 1)
  const s = t * c
  for (let k = 0; k < n; k++) {
    const akp = a[k][p]
    const akq = a[k][q]
    a[k][p] = c * akp - s * akq
    a[k][q] = s * akp + c * akq
  }
  for (let k = 0; k < n; k++) {
    const apk = a[p][k]
    const aqk = a[q][k]
    a[p][k] = c * apk - s * aqk
    a[q][k] = s * apk + c * aqk
  }
}

function eigenvalues(m) {
  const a = m.map((row) => Float64Array.from(row))
  const n = a.length
  const off = () => a.reduce((s, row, i) => s + row.reduce((t, v, j) => t + (i === j ? 0 : v * v), 0), 0)
  for (let sweep = 0; sweep < 100 && off() > 1e-22; sweep++) {
    for (let p = 0; p < n; p++) for (let q = p + 1; q < n; q++) if (a[p][q] !== 0) rotate(a, p, q)
  }
  return a.map((row, i) => row[i]).sort((x, y) => x - y)
}

export function solve(buf) {
  const nums = buf.toString().trim().split(/\s+/).map(Number)
  const n = nums[0]
  const a = Array.from({ length: n }, (_, i) => nums.slice(1 + i * n, 1 + (i + 1) * n))
  const b = nums.slice(1 + n * n, 1 + n * n + n)
  const { z, l } = choleskySolve(a, b)
  const logdet = 2 * l.reduce((s, row, i) => s + Math.log(row[i]), 0)
  const frob = Math.sqrt(a.reduce((s, row) => s + row.reduce((t, v) => t + v * v, 0), 0))
  const fmt = (v) => v.toPrecision(15)
  return [fmt(logdet), Array.from(z, fmt).join(' '), eigenvalues(a).map(fmt).join(' '), fmt(frob)].join('\n')
}

if (process.argv[1] === fileURLToPath(import.meta.url)) process.stdout.write(solve(readFileSync(0)) + '\n')
