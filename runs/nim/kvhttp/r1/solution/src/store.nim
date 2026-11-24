## In-memory key-value storage.

import std/[tables, algorithm]

type
  Store* = object
    data: Table[string, string]

  PutResult* = enum
    prCreated, prReplaced

proc initStore*(): Store =
  Store(data: initTable[string, string]())

proc put*(s: var Store, key: sink string, value: sink string): PutResult =
  result = if s.data.hasKey(key): prReplaced else: prCreated
  s.data[key] = value

proc get*(s: Store, key: string, value: var string): bool =
  ## Copies the stored value into `value`; returns false if `key` is absent.
  s.data.withValue(key, v):
    value = v
    return true
  false

proc delete*(s: var Store, key: string): bool =
  ## Removes `key`; returns false if it was absent.
  var discarded: string
  s.data.pop(key, discarded)

proc sortedKeys*(s: Store): seq[string] =
  result = newSeqOfCap[string](s.data.len)
  for k in s.data.keys:
    result.add k
  result.sort(system.cmp[string])
