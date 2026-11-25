## kvhttp: an in-memory HTTP/1.1 key-value server.

import std/[asyncdispatch, asynchttpserver, algorithm, json, os, strutils, tables]

const
  MaxValueSize = 1 shl 20     ## 1 MiB
  MaxKeyLen = 64
  KeyChars = {'A'..'Z', 'a'..'z', '0'..'9', '_', '-'}
  KvPrefix = "/kv/"

type Store = ref object
  data: Table[string, string]

func isValidKey(key: string): bool =
  key.len in 1..MaxKeyLen and key.allCharsInSet(KeyChars)

proc respondEmpty(req: Request, code: HttpCode): Future[void] =
  req.respond(code, "")

proc handleHealth(req: Request): Future[void] =
  if req.reqMethod == HttpGet: req.respond(Http200, "ok")
  else: req.respondEmpty(Http405)

proc handleList(store: Store, req: Request): Future[void] =
  if req.reqMethod != HttpGet:
    return req.respondEmpty(Http405)
  var keys = newSeqOfCap[string](store.data.len)
  for k in store.data.keys: keys.add k
  keys.sort()
  let headers = newHttpHeaders({"Content-Type": "application/json"})
  req.respond(Http200, $(%keys), headers)

proc handleKey(store: Store, req: Request, key: string): Future[void] =
  case req.reqMethod
  of HttpGet, HttpPut, HttpDelete:
    if not key.isValidKey:
      return req.respondEmpty(Http400)
  else:
    return req.respondEmpty(Http405)

  case req.reqMethod
  of HttpGet:
    store.data.withValue(key, value):
      return req.respond(Http200, value[])
    req.respondEmpty(Http404)
  of HttpPut:
    if req.body.len > MaxValueSize:
      return req.respondEmpty(Http413)
    let existed = key in store.data
    store.data[key] = req.body
    req.respondEmpty(if existed: Http200 else: Http201)
  of HttpDelete:
    var removed: string
    if store.data.pop(key, removed): req.respondEmpty(Http204)
    else: req.respondEmpty(Http404)
  else:
    req.respondEmpty(Http405)

proc route(store: Store, req: Request): Future[void] =
  let path = req.url.path
  if path == "/health":
    handleHealth(req)
  elif path == "/kv":
    store.handleList(req)
  elif path.startsWith(KvPrefix):
    store.handleKey(req, path.substr(KvPrefix.len))
  else:
    req.respondEmpty(Http404)

proc serve(port: Port) {.async.} =
  let store = Store(data: initTable[string, string]())
  let server = newAsyncHttpServer(maxBody = MaxValueSize)
  proc cb(req: Request) {.async, gcsafe.} =
    await store.route(req)
  await server.serve(port, cb, address = "127.0.0.1", assumedDescriptorsPerRequest = 5)

proc main() =
  if paramCount() != 1:
    quit("usage: app <port>", QuitFailure)
  let port =
    try: parseInt(paramStr(1))
    except ValueError: quit("invalid port: " & paramStr(1), QuitFailure)
  if port notin 1..65535:
    quit("invalid port: " & $port, QuitFailure)
  waitFor serve(Port(port))

when isMainModule:
  main()
