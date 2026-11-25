## LRU cache simulator: reads a capacity and a list of commands on stdin,
## writes command results on stdout. Every command runs in O(1) expected time.

import std/[strutils, tables]

const Nil = -1'i32

type
  Node = object
    key, value: string
    prev, next: int32

  LruCache = object
    capacity: int
    index: Table[string, int32]   ## key -> slot in `nodes`
    nodes: seq[Node]
    free: seq[int32]              ## recycled slots
    head, tail: int32             ## head = most recent, tail = least recent

proc initLruCache(capacity: int): LruCache =
  LruCache(capacity: capacity,
           index: initTable[string, int32](),
           nodes: newSeqOfCap[Node](min(capacity, 1 shl 16) + 1),
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
  let found = c.index.getOrDefault(key, Nil)
  if found != Nil:
    c.nodes[found].value = value
    c.touch(found)
    return
  var slot: int32
  if c.free.len > 0:
    slot = c.free.pop()
    c.nodes[slot].key = key
    c.nodes[slot].value = value
  else:
    slot = int32(c.nodes.len)
    c.nodes.add Node(key: key, value: value)
  c.index[key] = slot
  c.pushFront(slot)
  if c.len > c.capacity:
    c.release(c.tail)

proc get(c: var LruCache; key: string; value: var string): bool =
  let found = c.index.getOrDefault(key, Nil)
  if found == Nil:
    return false
  c.touch(found)
  value = c.nodes[found].value
  true

proc del(c: var LruCache; key: string): bool =
  let found = c.index.getOrDefault(key, Nil)
  if found == Nil:
    return false
  c.release(found)
  true

proc run(input: string): string =
  result = newStringOfCap(1 shl 16)
  var
    cache: LruCache
    haveCapacity = false
    value: string
  for raw in input.splitLines:
    let line = raw.strip(leading = false, chars = {'\r'})
    if line.len == 0:
      continue
    if not haveCapacity:
      cache = initLruCache(parseInt(line.strip))
      haveCapacity = true
      continue
    let parts = line.split(' ')
    case parts[0]
    of "SET":
      if parts.len >= 3:
        cache.set(parts[1], parts[2])
    of "GET":
      if parts.len >= 2:
        if cache.get(parts[1], value):
          result.add value
        else:
          result.add "NULL"
        result.add '\n'
    of "DEL":
      if parts.len >= 2:
        result.add(if cache.del(parts[1]): '1' else: '0')
        result.add '\n'
    of "SIZE":
      result.addInt cache.len
      result.add '\n'
    else:
      discard

proc main() =
  stdout.write run(stdin.readAll)
  flushFile(stdout)

when isMainModule:
  main()
