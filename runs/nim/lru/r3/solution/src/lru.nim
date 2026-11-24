## LRU cache simulator: reads a capacity and a command stream from stdin,
## writes query results to stdout. Every command runs in O(1) expected time.

import std/[tables, strutils]

const Nil = -1'i32

type
  Node = object
    key, value: string
    prev, next: int32

  LruCache = object
    capacity: int
    nodes: seq[Node]        ## slot storage; slots are recycled via `free`
    free: seq[int32]
    index: Table[string, int32]
    head, tail: int32       ## head = most recently used, tail = least

proc initLruCache(capacity: int): LruCache =
  LruCache(capacity: capacity, head: Nil, tail: Nil,
           index: initTable[string, int32](min(capacity, 1 shl 20)))

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

proc allocSlot(c: var LruCache): int32 =
  if c.free.len > 0:
    result = c.free.pop()
  else:
    result = int32(c.nodes.len)
    c.nodes.add Node()

proc set(c: var LruCache, key, value: string) =
  let existing = c.index.getOrDefault(key, Nil)
  if existing != Nil:
    c.nodes[existing].value = value
    c.touch(existing)
    return
  if c.len >= c.capacity:
    c.release(c.tail)
  let i = c.allocSlot()
  c.nodes[i].key = key
  c.nodes[i].value = value
  c.index[key] = i
  c.pushFront(i)

proc get(c: var LruCache, key: string): int32 =
  ## Returns the slot holding `key` (marking it most recently used), or `Nil`.
  result = c.index.getOrDefault(key, Nil)
  if result != Nil: c.touch(result)

func valueAt(c: LruCache, slot: int32): lent string {.inline.} =
  c.nodes[slot].value

proc del(c: var LruCache, key: string): bool =
  let i = c.index.getOrDefault(key, Nil)
  if i == Nil: return false
  c.release(i)
  true

proc nextToken(line: string, pos: var int, tok: var string) =
  ## Copies the next space-delimited token of `line` into `tok`.
  while pos < line.len and line[pos] == ' ': inc pos
  let start = pos
  while pos < line.len and line[pos] != ' ': inc pos
  tok.setLen(pos - start)
  if pos > start:
    copyMem(addr tok[0], unsafeAddr line[start], pos - start)

proc main() =
  let input = stdin.readAll()
  var output = newStringOfCap(1 shl 16)
  var cmd, key, value, line: string
  var pos = 0

  proc readLine(): bool =
    if pos >= input.len: return false
    var e = input.find('\n', pos)
    if e < 0: e = input.len
    var stop = e
    if stop > pos and input[stop - 1] == '\r': dec stop
    line = input.substr(pos, stop - 1)
    pos = e + 1
    true

  if not readLine(): return
  let capacity = max(1, parseInt(line.strip()))
  var cache = initLruCache(capacity)

  while readLine():
    var p = 0
    nextToken(line, p, cmd)
    case cmd
    of "SET":
      nextToken(line, p, key)
      nextToken(line, p, value)
      cache.set(key, value)
    of "GET":
      nextToken(line, p, key)
      let slot = cache.get(key)
      if slot != Nil: output.add cache.valueAt(slot) else: output.add "NULL"
      output.add '\n'
    of "DEL":
      nextToken(line, p, key)
      output.add(if cache.del(key): "1\n" else: "0\n")
    of "SIZE":
      output.addInt cache.len
      output.add '\n'
    else:
      discard  # blank or unrecognised line: ignore
    if output.len >= 1 shl 16:
      stdout.write output
      output.setLen(0)

  stdout.write output
  stdout.flushFile()

when isMainModule:
  main()
