'use strict'

const fs = require('node:fs')
const { LRUCache } = require('./lru.js')

function writeAll(fd, data) {
  const buf = Buffer.from(data)
  let off = 0
  while (off < buf.length) {
    try {
      off += fs.writeSync(fd, buf, off)
    } catch (err) {
      if (err.code !== 'EAGAIN') throw err
    }
  }
}

function main() {
  const input = fs.readFileSync(0, 'latin1')
  const lines = input.split('\n')
  const capacity = Number.parseInt(lines[0], 10)
  const cache = new LRUCache(capacity)
  const out = []

  for (let i = 1; i < lines.length; i++) {
    let line = lines[i]
    if (line.endsWith('\r')) line = line.slice(0, -1)
    if (line === '') continue
    const sp1 = line.indexOf(' ')
    const cmd = sp1 === -1 ? line : line.slice(0, sp1)
    switch (cmd) {
      case 'SET': {
        const sp2 = line.indexOf(' ', sp1 + 1)
        cache.set(line.slice(sp1 + 1, sp2), line.slice(sp2 + 1))
        break
      }
      case 'GET': {
        const value = cache.get(line.slice(sp1 + 1))
        out.push(value === undefined ? 'NULL' : value)
        break
      }
      case 'DEL':
        out.push(cache.delete(line.slice(sp1 + 1)) ? '1' : '0')
        break
      case 'SIZE':
        out.push(String(cache.size))
        break
      default:
        break // ignore unknown commands
    }
  }

  if (out.length > 0) writeAll(1, out.join('\n') + '\n')
}

main()
