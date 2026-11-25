## kvhttp: an in-memory HTTP/1.1 key-value server.

import std/[asyncdispatch, asynchttpserver, algorithm, json, os, strutils, tables]

const
  MaxKeyLen = 64
  MaxValueLen = 1024 * 1024
  KeyChars = {'A'..'Z', 'a'..'z', '0'..'9', '_', '-'}
  KvPrefix = "/kv/"

type Store = ref object
  data: Table[string, string]

func isValidKey(key: string): bool =
  key.len in 1..MaxKeyLen and key.allCharsInSet(KeyChars)

proc reply(req: Request; code: HttpCode; body = "";
           headers = newHttpHeaders()): Future[void] =
  headers["Connection"] = "close"
  req.respond(code, body, headers)

proc methodNotAllowed(req: Request; allow: string): Future[void] =
  req.reply(Http405, headers = newHttpHeaders({"Allow": allow}))

proc handleList(store: Store; req: Request): Future[void] =
  if req.reqMethod != HttpGet:
    return req.methodNotAllowed("GET")
  var keys = newSeqOfCap[string](store.data.len)
  for k in store.data.keys:
    keys.add k
  keys.sort()
  req.reply(Http200, $(%keys),
            newHttpHeaders({"Content-Type": "application/json"}))

proc handleKey(store: Store; req: Request; key: string): Future[void] =
  if not key.isValidKey:
    return req.reply(Http400)
  case req.reqMethod
  of HttpGet:
    store.data.withValue(key, value):
      return req.reply(Http200, value[],
                       newHttpHeaders({"Content-Type": "application/octet-stream"}))
    req.reply(Http404)
  of HttpPut:
    if req.body.len > MaxValueLen:
      return req.reply(Http413)
    let existed = key in store.data
    store.data[key] = req.body
    req.reply(if existed: Http200 else: Http201)
  of HttpDelete:
    var discarded: string
    if store.data.pop(key, discarded):
      req.reply(Http204)
    else:
      req.reply(Http404)
  else:
    req.methodNotAllowed("GET, PUT, DELETE")

proc handle(store: Store; req: Request): Future[void] =
  let path = req.url.path
  if path == "/health":
    if req.reqMethod == HttpGet:
      req.reply(Http200, "ok", newHttpHeaders({"Content-Type": "text/plain"}))
    else:
      req.methodNotAllowed("GET")
  elif path == "/kv":
    store.handleList(req)
  elif path.startsWith(KvPrefix):
    store.handleKey(req, path[KvPrefix.len .. ^1])
  else:
    req.reply(Http404)

proc serve(port: Port) {.async.} =
  let store = Store(data: initTable[string, string]())
  let server = newAsyncHttpServer(maxBody = MaxValueLen + 1)
  server.listen(port, "127.0.0.1")
  proc callback(req: Request): Future[void] {.gcsafe.} = store.handle(req)
  while true:
    if server.shouldAcceptRequest():
      await server.acceptRequest(callback)
    else:
      await sleepAsync(10)

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
