## LRU cache simulator: reads a capacity and a command stream from stdin,
## writes command results to stdout. Every command runs in O(1) expected time.

import std/[tables, strutils]

const Nil = -1'i32

type
  Node = object
    key, value: string
    prev, next: int32

  LruCache = object
    capacity: int
    index: Table[string, int32]
    nodes: seq[Node]
    free: seq[int32]
    head, tail: int32       ## head = most recently used, tail = least

proc initLruCache(capacity: int): LruCache =
  LruCache(capacity: capacity,
           index: initTable[string, int32](),
           head: Nil, tail: Nil)

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

proc touch(c: var LruCache, i: int32) =
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
  c.index.withValue(key, slot):
    c.nodes[slot[]].value = value
    c.touch(slot[])
    return
  var i: int32
  if c.free.len > 0:
    i = c.free.pop()
    c.nodes[i].key = key
    c.nodes[i].value = value
  else:
    i = int32(c.nodes.len)
    c.nodes.add Node(key: key, value: value)
  c.index[c.nodes[i].key] = i
  c.pushFront(i)
  if c.len > c.capacity:
    c.release(c.tail)

proc lookup(c: var LruCache, key: string): int32 =
  ## Returns the node index for `key` (marking it most recently used), or `Nil`.
  result = c.index.getOrDefault(key, Nil)
  if result != Nil: c.touch(result)

proc del(c: var LruCache, key: string): bool =
  let i = c.index.getOrDefault(key, Nil)
  result = i != Nil
  if result: c.release(i)

iterator lines(data: string): string =
  var start = 0
  while start < data.len:
    var stop = data.find('\n', start)
    if stop < 0: stop = data.len
    var e = stop
    if e > start and data[e - 1] == '\r': dec e
    yield data[start ..< e]
    start = stop + 1

proc main() =
  let input = stdin.readAll()
  var
    cache: LruCache
    initialized = false
    output = newStringOfCap(1 shl 16)

  for line in input.lines:
    if not initialized:
      let s = line.strip()
      if s.len == 0: continue
      cache = initLruCache(parseInt(s))
      initialized = true
      continue
    let parts = line.splitWhitespace(maxsplit = 2)
    if parts.len == 0: continue
    case parts[0]
    of "SET":
      if parts.len >= 3: cache.set(parts[1], parts[2])
    of "GET":
      if parts.len >= 2:
        let i = cache.lookup(parts[1])
        output.add(if i != Nil: cache.nodes[i].value else: "NULL")
        output.add '\n'
    of "DEL":
      if parts.len >= 2:
        output.add(if cache.del(parts[1]): '1' else: '0')
        output.add '\n'
    of "SIZE":
      output.addInt cache.len
      output.add '\n'
    else: discard

  stdout.write output
  stdout.flushFile()

when isMainModule:
  main()
