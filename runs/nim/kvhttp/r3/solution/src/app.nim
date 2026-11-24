## kvhttp: a small in-memory HTTP/1.1 key-value server.
##
## Usage: app <port>

import std/[asyncdispatch, asyncnet, json, net, os, parseutils, strutils,
            tables, algorithm]

const
  MaxValueSize = 1 shl 20      ## 1 MiB
  MaxKeyLen = 64
  MaxLineLen = 8 * 1024
  MaxHeaders = 100
  KvPrefix = "/kv/"

type
  Request = object
    meth: string
    path: string
    version: string
    headers: Table[string, string] ## lower-cased names
    body: string

  Response = object
    status: int
    contentType: string
    body: string

  Store = Table[string, string]

  ParseError = object of CatchableError
    status: int

var store: Store

func reason(status: int): string =
  case status
  of 200: "OK"
  of 201: "Created"
  of 204: "No Content"
  of 400: "Bad Request"
  of 404: "Not Found"
  of 405: "Method Not Allowed"
  of 411: "Length Required"
  of 413: "Content Too Large"
  of 431: "Request Header Fields Too Large"
  of 500: "Internal Server Error"
  of 501: "Not Implemented"
  else: "Unknown"

func isValidKey(key: string): bool =
  key.len in 1..MaxKeyLen and key.allCharsInSet({'A'..'Z', 'a'..'z', '0'..'9', '_', '-'})

func resp(status: int; body = ""; contentType = ""): Response =
  Response(status: status, body: body, contentType: contentType)

func methodNotAllowed(): Response = resp(405)

proc handle(req: Request): Response =
  ## Routes a parsed request against the in-memory store.
  if req.path == "/health":
    if req.meth == "GET": resp(200, "ok", "text/plain")
    else: methodNotAllowed()
  elif req.path == "/kv":
    if req.meth == "GET":
      var keys = newSeqOfCap[string](store.len)
      for k in store.keys: keys.add k
      keys.sort(system.cmp[string])
      resp(200, $(%keys), "application/json")
    else: methodNotAllowed()
  elif req.path.startsWith(KvPrefix):
    let key = req.path[KvPrefix.len .. ^1]
    if not isValidKey(key):
      return resp(400)
    case req.meth
    of "GET":
      store.withValue(key, value):
        return resp(200, value[], "application/octet-stream")
      resp(404)
    of "PUT":
      let existed = key in store
      store[key] = req.body
      resp(if existed: 200 else: 201)
    of "DELETE":
      if store.hasKey(key):
        store.del key
        resp(204)
      else:
        resp(404)
    else: methodNotAllowed()
  else:
    resp(404)

proc raiseParse(status: int; msg: string) {.noreturn.} =
  var e = newException(ParseError, msg)
  e.status = status
  raise e

proc readLine(client: AsyncSocket): Future[string] {.async.} =
  result = await client.recvLine(maxLength = MaxLineLen)
  if result.len > MaxLineLen:
    raiseParse(431, "line too long")

proc readRequest(client: AsyncSocket): Future[(bool, Request)] {.async.} =
  ## Reads one request. Returns `(false, _)` on a clean EOF before any data.
  var req: Request
  var line = await client.readLine()
  # Tolerate stray empty lines before the request line (RFC 9112 §2.2).
  while line == "\c\L":
    line = await client.readLine()
  if line.len == 0:
    return (false, req)

  let parts = line.splitWhitespace()
  if parts.len != 3 or not parts[2].startsWith("HTTP/1."):
    raiseParse(400, "malformed request line")
  req.meth = parts[0]
  req.version = parts[2]
  var target = parts[1]
  let q = target.find({'?', '#'})
  if q >= 0: target.setLen(q)
  req.path = target

  while true:
    let h = await client.readLine()
    if h.len == 0:
      raiseParse(400, "unexpected end of headers")
    if h == "\c\L":
      break
    if req.headers.len >= MaxHeaders:
      raiseParse(431, "too many headers")
    let colon = h.find(':')
    if colon <= 0:
      raiseParse(400, "malformed header")
    let name = h[0 ..< colon].strip.toLowerAscii
    let value = h[colon + 1 .. ^1].strip
    if name == "content-length" and req.headers.hasKey(name) and
        req.headers[name] != value:
      raiseParse(400, "conflicting Content-Length")
    req.headers[name] = value

  if req.headers.hasKey("transfer-encoding"):
    raiseParse(501, "Transfer-Encoding not supported")

  let cl = req.headers.getOrDefault("content-length")
  if cl.len > 0:
    var n: int
    if cl.parseSaturatedNatural(n) != cl.len:
      raiseParse(400, "invalid Content-Length")
    if n > MaxValueSize:
      raiseParse(413, "body too large")
    if n > 0:
      req.body = await client.recv(n)
      if req.body.len != n:
        raiseParse(400, "truncated body")
  return (true, req)

func wantsKeepAlive(req: Request): bool =
  let conn = req.headers.getOrDefault("connection").toLowerAscii
  if req.version == "HTTP/1.0": "keep-alive" in conn
  else: "close" notin conn

proc send(client: AsyncSocket; r: Response; keepAlive: bool) {.async.} =
  var msg = newStringOfCap(r.body.len + 128)
  msg.add "HTTP/1.1 " & $r.status & " " & reason(r.status) & "\c\L"
  if r.contentType.len > 0:
    msg.add "Content-Type: " & r.contentType & "\c\L"
  if r.status != 204:
    msg.add "Content-Length: " & $r.body.len & "\c\L"
  msg.add(if keepAlive: "Connection: keep-alive\c\L" else: "Connection: close\c\L")
  msg.add "\c\L"
  if r.status != 204:
    msg.add r.body
  await client.send(msg)

proc serveClient(client: AsyncSocket) {.async.} =
  try:
    while true:
      var keepAlive = false
      var response: Response
      try:
        let (ok, req) = await client.readRequest()
        if not ok: break
        keepAlive = req.wantsKeepAlive
        response = handle(req)
      except ParseError as e:
        response = resp(e.status, e.msg & "\n", "text/plain")
      await client.send(response, keepAlive)
      if not keepAlive: break
  except CatchableError:
    discard # connection-level failure: drop the client
  finally:
    client.close()

proc serve(port: Port) {.async.} =
  let server = newAsyncSocket()
  server.setSockOpt(OptReuseAddr, true)
  server.bindAddr(port, "127.0.0.1")
  server.listen(backlog = 1024)
  while true:
    let client = await server.accept()
    asyncCheck serveClient(client)

proc main() =
  let args = commandLineParams()
  var port: int
  if args.len != 1 or args[0].parseInt(port) != args[0].len or port notin 1..65535:
    quit("usage: app <port>", QuitFailure)
  waitFor serve(Port(port))

when isMainModule:
  main()
