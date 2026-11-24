## Maps a parsed request onto the key-value store. Pure with respect to I/O so
## that it can be exercised without a socket.

import std/[json, strutils]
import store

const
  MaxKeyLen* = 64
  KvPrefix = "/kv/"

type
  Response* = object
    status*: int
    contentType*: string
    allow*: string          ## Set for 405 responses.
    body*: string

func isValidKey*(key: string): bool =
  key.len in 1..MaxKeyLen and key.allCharsInSet(IdentChars + {'-'})

func reply(status: int, body = "", contentType = ""): Response =
  Response(status: status, body: body, contentType: contentType)

func methodNotAllowed(allow: string): Response =
  Response(status: 405, allow: allow, body: "method not allowed",
           contentType: "text/plain")

proc handleKey(s: var Store, meth, key: string, body: sink string): Response =
  case meth
  of "GET":
    var value: string
    if s.get(key, value): reply(200, value, "application/octet-stream")
    else: reply(404, "not found", "text/plain")
  of "PUT":
    case s.put(key, body)
    of prCreated: reply(201)
    of prReplaced: reply(200)
  of "DELETE":
    if s.delete(key): reply(204)
    else: reply(404, "not found", "text/plain")
  else:
    methodNotAllowed("GET, PUT, DELETE")

proc route*(s: var Store, meth, path: string, body: sink string): Response =
  if path == "/health":
    if meth == "GET": reply(200, "ok", "text/plain")
    else: methodNotAllowed("GET")
  elif path == "/kv":
    if meth == "GET": reply(200, $(%s.sortedKeys), "application/json")
    else: methodNotAllowed("GET")
  elif path.startsWith(KvPrefix):
    let key = path[KvPrefix.len .. ^1]
    if key.isValidKey: s.handleKey(meth, key, body)
    else: reply(400, "invalid key", "text/plain")
  else:
    reply(404, "not found", "text/plain")
