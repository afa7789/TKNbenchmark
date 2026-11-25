## LRU cache simulator: reads a capacity and a stream of commands from stdin.

import std/[strutils, tables]

const Nil = -1

type
  Node = object
    key, value: string
    prev, next: int

  LruCache = object
    capacity: int
    nodes: seq[Node]          ## node storage; slots are recycled via `free`
    free: seq[int]
    index: Table[string, int] ## key -> slot in `nodes`
    head, tail: int           ## head = most recently used

proc initLruCache(capacity: int): LruCache =
  LruCache(capacity: capacity, head: Nil, tail: Nil,
           nodes: newSeqOfCap[Node](min(capacity + 1, 1 shl 16)),
           index: initTable[string, int]())

func len(c: LruCache): int {.inline.} = c.index.len

proc unlink(c: var LruCache; i: int) =
  let (p, n) = (c.nodes[i].prev, c.nodes[i].next)
  if p == Nil: c.head = n else: c.nodes[p].next = n
  if n == Nil: c.tail = p else: c.nodes[n].prev = p

proc pushFront(c: var LruCache; i: int) =
  c.nodes[i].prev = Nil
  c.nodes[i].next = c.head
  if c.head != Nil: c.nodes[c.head].prev = i
  c.head = i
  if c.tail == Nil: c.tail = i

proc touch(c: var LruCache; i: int) {.inline.} =
  if c.head != i:
    c.unlink(i)
    c.pushFront(i)

proc release(c: var LruCache; i: int) =
  c.unlink(i)
  c.index.del(c.nodes[i].key)
  c.nodes[i].key.setLen(0)
  c.nodes[i].value.setLen(0)
  c.free.add i

proc set(c: var LruCache; key, value: sink string) =
  c.index.withValue(key, slot):
    c.nodes[slot[]].value = value
    c.touch(slot[])
    return
  var i: int
  if c.free.len > 0:
    i = c.free.pop()
    c.nodes[i].key = key
    c.nodes[i].value = value
  else:
    i = c.nodes.len
    c.nodes.add Node(key: key, value: value)
  c.index[c.nodes[i].key] = i
  c.pushFront(i)
  if c.len > c.capacity:
    c.release(c.tail)

proc get(c: var LruCache; key: string): int =
  ## Returns the slot holding `key` (marking it most recently used), or `Nil`.
  result = c.index.getOrDefault(key, Nil)
  if result != Nil: c.touch(result)

func valueAt(c: LruCache; slot: int): lent string {.inline.} = c.nodes[slot].value

proc del(c: var LruCache; key: string): bool =
  let i = c.index.getOrDefault(key, Nil)
  result = i != Nil
  if result: c.release(i)

iterator tokens(line: string): string =
  for tok in line.split(' '):
    if tok.len > 0: yield tok

proc main() =
  let input = stdin.readAll()
  var
    output = newStringOfCap(1 shl 20)
    cache: LruCache
    haveCapacity = false
    parts = newSeqOfCap[string](3)
  for raw in input.splitLines():
    let line = raw.strip(leading = false, chars = {'\r', ' '})
    if line.len == 0: continue
    if not haveCapacity:
      cache = initLruCache(max(1, parseInt(line.strip())))
      haveCapacity = true
      continue
    parts.setLen(0)
    for tok in line.tokens: parts.add tok
    case parts[0]
    of "SET":
      if parts.len >= 3: cache.set(move parts[1], move parts[2])
    of "GET":
      if parts.len >= 2:
        let slot = cache.get(parts[1])
        output.add(if slot == Nil: "NULL" else: cache.valueAt(slot))
        output.add '\n'
    of "DEL":
      if parts.len >= 2:
        output.add(if cache.del(parts[1]): "1\n" else: "0\n")
    of "SIZE":
      output.addInt cache.len
      output.add '\n'
    else: discard
  stdout.write output
  stdout.flushFile()

when isMainModule:
  main()
