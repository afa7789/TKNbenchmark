## LRU cache simulator: reads a capacity and a stream of commands from stdin.

import std/[tables, strutils]

const Nil = -1'i32

type
  Node = object
    key, value: string
    prev, next: int32

  LruCache = object
    capacity: int
    nodes: seq[Node]        ## slot storage; freed slots are reused via `free`
    free: seq[int32]
    index: Table[string, int32]
    head, tail: int32       ## head = most recently used, tail = least

proc initLruCache(capacity: int): LruCache =
  result = LruCache(capacity: capacity, head: Nil, tail: Nil)
  let hint = min(capacity, 1 shl 20)
  result.index = initTable[string, int32](hint)
  result.nodes = newSeqOfCap[Node](hint)

func len(c: LruCache): int {.inline.} = c.index.len

proc unlink(c: var LruCache, i: int32) =
  let (p, n) = (c.nodes[i].prev, c.nodes[i].next)
  if p == Nil: c.head = n else: c.nodes[p].next = n
  if n == Nil: c.tail = p else: c.nodes[n].prev = p

proc pushFront(c: var LruCache, i: int32) =
  c.nodes[i].prev = Nil
  c.nodes[i].next = c.head
  if c.head != Nil: c.nodes[c.head].prev = i
  c.head = i
  if c.tail == Nil: c.tail = i

proc touch(c: var LruCache, i: int32) {.inline.} =
  if c.head != i:
    c.unlink(i)
    c.pushFront(i)

proc release(c: var LruCache, i: int32) =
  c.unlink(i)
  c.index.del(c.nodes[i].key)
  c.nodes[i].key.setLen(0)
  c.nodes[i].value.setLen(0)
  c.free.add i

proc set(c: var LruCache, key, value: sink string) =
  let found = c.index.getOrDefault(key, Nil)
  if found != Nil:
    c.nodes[found].value = value
    c.touch(found)
    return
  var i: int32
  if c.free.len > 0:
    i = c.free.pop()
    c.nodes[i].key = key
    c.nodes[i].value = value
  else:
    i = int32(c.nodes.len)
    c.nodes.add Node(key: key, value: value, prev: Nil, next: Nil)
  c.index[c.nodes[i].key] = i
  c.pushFront(i)
  if c.len > c.capacity:
    c.release(c.tail)

proc get(c: var LruCache, key: string, value: var string): bool =
  let i = c.index.getOrDefault(key, Nil)
  if i == Nil: return false
  c.touch(i)
  value = c.nodes[i].value
  true

proc delete(c: var LruCache, key: string): bool =
  let i = c.index.getOrDefault(key, Nil)
  if i == Nil: return false
  c.release(i)
  true

proc main() =
  let input = stdin.readAll()
  var
    output = newStringOfCap(1 shl 16)
    cache: LruCache
    initialized = false
    value: string

  for raw in input.splitLines():
    let line = raw.strip(leading = false, chars = {'\r', ' ', '\t'})
    if line.len == 0: continue
    if not initialized:
      cache = initLruCache(max(1, parseInt(line.strip())))
      initialized = true
      continue
    let parts = line.splitWhitespace()
    case parts[0]
    of "SET":
      if parts.len >= 3: cache.set(parts[1], parts[2])
    of "GET":
      if parts.len >= 2:
        if cache.get(parts[1], value): output.add value
        else: output.add "NULL"
        output.add '\n'
    of "DEL":
      if parts.len >= 2:
        output.add(if cache.delete(parts[1]): "1\n" else: "0\n")
    of "SIZE":
      output.add $cache.len
      output.add '\n'
    else:
      discard
    if output.len >= 1 shl 16:
      stdout.write output
      output.setLen(0)

  stdout.write output
  stdout.flushFile()

when isMainModule:
  main()
