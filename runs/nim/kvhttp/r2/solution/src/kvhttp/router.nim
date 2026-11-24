## Request routing for the key-value API. Pure logic: no sockets involved,
## so it can be exercised directly from unit tests.

import std/[algorithm, httpcore, json, strutils, tables]

const
  MaxKeyLen* = 64
  MaxValueLen* = 1 shl 20 ## 1 MiB

type
  Store* = Table[string, string]

  Response* = object
    code*: HttpCode
    body*: string
    contentType*: string ## Empty means no Content-Type header.

proc initResponse(code: HttpCode; body = ""; contentType = ""): Response =
  Response(code: code, body: body, contentType: contentType)

func isValidKey*(key: string): bool =
  const KeyChars = {'A'..'Z', 'a'..'z', '0'..'9', '_', '-'}
  key.len in 1..MaxKeyLen and key.allCharsInSet(KeyChars)

proc listKeys(store: Store): Response =
  var keys = newSeqOfCap[string](store.len)
  for k in store.keys:
    keys.add k
  keys.sort(system.cmp[string])
  initResponse(Http200, $(%keys), "application/json")

proc handleKey(store: var Store; meth, key, body: string): Response =
  if not key.isValidKey:
    return initResponse(Http400)
  case meth
  of "GET":
    store.withValue(key, value):
      return initResponse(Http200, value[], "application/octet-stream")
    do:
      return initResponse(Http404)
  of "PUT":
    if body.len > MaxValueLen:
      return initResponse(Http413)
    let existed = store.hasKey(key)
    store[key] = body
    initResponse(if existed: Http200 else: Http201)
  of "DELETE":
    if store.hasKey(key):
      store.del(key)
      initResponse(Http204)
    else:
      initResponse(Http404)
  else:
    initResponse(Http405)

proc route*(store: var Store; meth, path, body: string): Response =
  ## Dispatches a request to the matching handler. `meth` is the request
  ## method exactly as sent (methods are case-sensitive per RFC 9110).
  const KeyPrefix = "/kv/"
  let path = path.split('?', maxsplit = 1)[0]
  if path == "/health":
    if meth == "GET": initResponse(Http200, "ok", "text/plain")
    else: initResponse(Http405)
  elif path == "/kv":
    if meth == "GET": store.listKeys()
    else: initResponse(Http405)
  elif path.startsWith(KeyPrefix):
    store.handleKey(meth, path.substr(KeyPrefix.len), body)
  else:
    initResponse(Http404)
