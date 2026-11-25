## LRU cache simulator: reads a capacity and a stream of commands from
## stdin, writes command results to stdout.

import std/[strutils, tables]

const Nil = -1'i32

type
  Node = object
    key, value: string
    prev, next: int32

  LruCache = object
    capacity: int
    nodes: seq[Node]          ## node storage; freed slots are reused
    free: seq[int32]          ## indices of unused slots in `nodes`
    index: Table[string, int32]
    head, tail: int32         ## head = most recently used

func initLruCache(capacity: int): LruCache =
  let reserve = min(capacity, 1 shl 16)
  LruCache(capacity: capacity,
           nodes: newSeqOfCap[Node](reserve + 1),
           index: initTable[string, int32](reserve),
           head: Nil, tail: Nil)

func len(c: LruCache): int {.inline.} = c.index.len

proc unlink(c: var LruCache; i: int32) =
  let (p, n) = (c.nodes[i].prev, c.nodes[i].next)
  if p == Nil: c.head = n else: c.nodes[p].next = n
  if n == Nil: c.tail = p else: c.nodes[n].prev = p

proc pushFront(c: var LruCache; i: int32) =
  c.nodes[i].prev = Nil
  c.nodes[i].next = c.head
  if c.head != Nil: c.nodes[c.head].prev = i
  c.head = i
  if c.tail == Nil: c.tail = i

proc touch(c: var LruCache; i: int32) {.inline.} =
  if c.head != i:
    c.unlink(i)
    c.pushFront(i)

proc release(c: var LruCache; i: int32) =
  c.unlink(i)
  c.index.del(c.nodes[i].key)
  c.nodes[i].key.setLen(0)
  c.nodes[i].value.setLen(0)
  c.free.add i

proc set(c: var LruCache; key, value: string) =
  var i = c.index.getOrDefault(key, Nil)
  if i != Nil:
    c.nodes[i].value = value
    c.touch(i)
    return
  if c.free.len > 0:
    i = c.free.pop()
    c.nodes[i].key = key
    c.nodes[i].value = value
  else:
    i = int32(c.nodes.len)
    c.nodes.add Node(key: key, value: value)
  c.index[key] = i
  c.pushFront(i)
  if c.len > c.capacity:
    c.release(c.tail)

proc get(c: var LruCache; key: string; value: var string): bool =
  let i = c.index.getOrDefault(key, Nil)
  if i == Nil: return false
  c.touch(i)
  value = c.nodes[i].value
  true

proc del(c: var LruCache; key: string): bool =
  let i = c.index.getOrDefault(key, Nil)
  if i == Nil: return false
  c.release(i)
  true

iterator commandLines(input: string): (int, int) =
  ## Yields [start, stop) bounds of each line, with any trailing '\r' dropped.
  var start = 0
  while start < input.len:
    var stop = input.find('\n', start)
    let next = if stop < 0: input.len else: stop + 1
    if stop < 0: stop = input.len
    var e = stop
    if e > start and input[e - 1] == '\r': dec e
    yield (start, e)
    start = next

proc run(input: string): string =
  result = newStringOfCap(1 shl 20)
  var cache: LruCache
  var haveCapacity = false
  var tokens: seq[string]
  var value: string
  for (a, b) in commandLines(input):
    let line = input[a ..< b]
    if not haveCapacity:
      let s = line.strip
      if s.len == 0: continue
      cache = initLruCache(parseInt(s))
      haveCapacity = true
      continue
    tokens = line.splitWhitespace
    if tokens.len == 0: continue
    case tokens[0]
    of "SET":
      if tokens.len >= 3: cache.set(tokens[1], tokens[2])
    of "GET":
      if tokens.len >= 2:
        if cache.get(tokens[1], value): result.add value
        else: result.add "NULL"
        result.add '\n'
    of "DEL":
      if tokens.len >= 2:
        result.add(if cache.del(tokens[1]): '1' else: '0')
        result.add '\n'
    of "SIZE":
      result.addInt cache.len
      result.add '\n'
    else: discard

proc main() =
  stdout.write run(stdin.readAll())
  flushFile(stdout)

when isMainModule:
  main()
