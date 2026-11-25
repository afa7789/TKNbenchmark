## kvhttp: an in-memory HTTP/1.1 key-value server.
##
## Usage: `app <port>` — listens on 127.0.0.1:<port>. One request per
## connection; every response carries a Content-Length and the connection
## is closed afterwards.

import std/[asyncdispatch, asyncnet, algorithm, json, nativesockets, os,
            strutils, tables]

const
  MaxValueSize = 1024 * 1024   ## Largest accepted value (1 MiB).
  MaxLineLen = 8 * 1024        ## Longest accepted request/header line.
  MaxHeaders = 100
  KvPrefix = "/kv/"

type
  Store = TableRef[string, string]

  Request = object
    meth: string
    path: string
    contentLength: int
    body: string

  Response = object
    status: int
    contentType: string
    body: string

  BadRequest = object of CatchableError
    status: int

func reason(status: int): string =
  case status
  of 200: "OK"
  of 201: "Created"
  of 204: "No Content"
  of 400: "Bad Request"
  of 404: "Not Found"
  of 405: "Method Not Allowed"
  of 413: "Content Too Large"
  of 431: "Request Header Fields Too Large"
  of 500: "Internal Server Error"
  else: "Unknown"

func initResponse(status: int; body = ""; contentType = "text/plain"): Response =
  Response(status: status, body: body, contentType: contentType)

func isValidKey(key: string): bool =
  key.len in 1..64 and key.allCharsInSet({'A'..'Z', 'a'..'z', '0'..'9', '_', '-'})

proc fail(status: int; msg: string) {.noreturn.} =
  var e = newException(BadRequest, msg)
  e.status = status
  raise e

# ---------------------------------------------------------------- routing

proc listKeys(store: Store): Response =
  var keys = newSeqOfCap[string](store.len)
  for k in store.keys: keys.add k
  keys.sort()
  initResponse(200, $(%keys), "application/json")

proc handleKey(store: Store; req: Request; key: string): Response =
  if not key.isValidKey:
    return initResponse(400, "invalid key")
  case req.meth
  of "GET":
    store[].withValue(key, value):
      return initResponse(200, value[], "application/octet-stream")
    initResponse(404, "not found")
  of "PUT":
    let existed = key in store
    store[key] = req.body
    initResponse(if existed: 200 else: 201)
  of "DELETE":
    if store.hasKey(key):
      store.del key
      initResponse(204)
    else:
      initResponse(404, "not found")
  else:
    initResponse(405, "method not allowed")

proc route(store: Store; req: Request): Response =
  if req.path == "/health":
    if req.meth == "GET": initResponse(200, "ok")
    else: initResponse(405, "method not allowed")
  elif req.path == "/kv":
    if req.meth == "GET": store.listKeys()
    else: initResponse(405, "method not allowed")
  elif req.path.startsWith(KvPrefix):
    store.handleKey(req, req.path[KvPrefix.len .. ^1])
  else:
    initResponse(404, "not found")

# ---------------------------------------------------------------- HTTP I/O

proc readLine(client: AsyncSocket): Future[string] {.async.} =
  result = await client.recvLine(maxLength = MaxLineLen + 1)
  if result.len > MaxLineLen:
    fail(431, "line too long")

proc readRequest(client: AsyncSocket): Future[Request] {.async.} =
  var line = await client.readLine()
  while line == "\c\L":            # tolerate stray blank lines before the request
    line = await client.readLine()
  if line.len == 0:
    raise newException(IOError, "client disconnected")

  let parts = line.splitWhitespace()
  if parts.len != 3 or not parts[2].startsWith("HTTP/"):
    fail(400, "malformed request line")
  result.meth = parts[0]
  result.path = parts[1]
  let q = result.path.find({'?', '#'})
  if q >= 0: result.path.setLen(q)

  var headerCount = 0
  while true:
    let header = await client.readLine()
    if header.len == 0:
      raise newException(IOError, "client disconnected")
    if header == "\c\L": break
    inc headerCount
    if headerCount > MaxHeaders:
      fail(431, "too many headers")
    let colon = header.find(':')
    if colon <= 0:
      fail(400, "malformed header")
    let name = header[0 ..< colon].strip()
    let value = header[colon + 1 .. ^1].strip()
    if name.cmpIgnoreCase("Content-Length") == 0:
      try:
        result.contentLength = parseInt(value)
      except ValueError:
        fail(400, "invalid Content-Length")
      if result.contentLength < 0:
        fail(400, "invalid Content-Length")
    elif name.cmpIgnoreCase("Transfer-Encoding") == 0:
      fail(400, "chunked bodies are not supported")

  if result.contentLength > MaxValueSize:
    fail(413, "value too large")
  if result.contentLength > 0:
    result.body = await client.recv(result.contentLength)
    if result.body.len != result.contentLength:
      raise newException(IOError, "truncated body")

proc send(client: AsyncSocket; resp: Response) {.async.} =
  var msg = newStringOfCap(128 + resp.body.len)
  msg.add "HTTP/1.1 " & $resp.status & " " & reason(resp.status) & "\c\L"
  if resp.status != 204:
    msg.add "Content-Type: " & resp.contentType & "\c\L"
  msg.add "Content-Length: " & $resp.body.len & "\c\L"
  msg.add "Connection: close\c\L\c\L"
  msg.add resp.body
  await client.send(msg)

proc serveClient(store: Store; client: AsyncSocket) {.async.} =
  try:
    let resp =
      try:
        store.route(await client.readRequest())
      except BadRequest as e:
        initResponse(e.status, e.msg)
    await client.send(resp)
  except CatchableError:
    discard                        # client went away; nothing to answer
  finally:
    client.close()

proc serve(port: Port) {.async.} =
  let store: Store = newTable[string, string]()
  let server = newAsyncSocket()
  server.setSockOpt(OptReuseAddr, true)
  server.bindAddr(port, "127.0.0.1")
  server.listen(backlog = 1024)
  while true:
    try:
      let client = await server.accept()
      asyncCheck store.serveClient(client)
    except OSError as e:           # e.g. EMFILE: back off briefly and retry
      stderr.writeLine "accept failed: ", e.msg
      await sleepAsync(10)

proc main() =
  if paramCount() != 1:
    quit "usage: app <port>", QuitFailure
  let port =
    try: parseInt(paramStr(1))
    except ValueError: -1
  if port notin 1..65535:
    quit "invalid port: " & paramStr(1), QuitFailure
  waitFor serve(Port(port))

when isMainModule:
  main()
