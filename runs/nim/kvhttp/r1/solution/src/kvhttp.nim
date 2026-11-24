## kvhttp: an in-memory HTTP/1.1 key-value server.
##
## Usage: kvhttp <port>

import std/[asyncdispatch, asyncnet, httpcore, net, os, strutils]
import store, router

const
  MaxBodyLen = 1 shl 20      ## 1 MiB, the largest accepted value.
  MaxLineLen = 8 * 1024
  MaxHeaders = 100

type
  Request = object
    meth, path: string
    keepAlive: bool
    body: string

  BadRequest = object of CatchableError
    status: int

var db = initStore()

proc fail(status: int, msg: string) {.noreturn.} =
  var e = newException(BadRequest, msg)
  e.status = status
  raise e

proc reasonPhrase(status: int): string =
  let full = $HttpCode(status)        # e.g. "404 Not Found"
  let sp = full.find(' ')
  if sp >= 0: full[sp + 1 .. ^1] else: "Unknown"

proc send(client: AsyncSocket, resp: Response, keepAlive: bool) {.async.} =
  var msg = newStringOfCap(128 + resp.body.len)
  msg.add "HTTP/1.1 " & $resp.status & " " & reasonPhrase(resp.status) & "\r\n"
  if resp.contentType.len > 0:
    msg.add "Content-Type: " & resp.contentType & "\r\n"
  if resp.allow.len > 0:
    msg.add "Allow: " & resp.allow & "\r\n"
  msg.add "Content-Length: " & $resp.body.len & "\r\n"
  msg.add(if keepAlive: "Connection: keep-alive\r\n" else: "Connection: close\r\n")
  msg.add "\r\n"
  msg.add resp.body
  await client.send(msg)

proc readLine(client: AsyncSocket): Future[string] {.async.} =
  ## Reads one CRLF-terminated line. Returns "" on EOF and "\r\n" for an
  ## empty line, mirroring `recvLine`.
  result = await client.recvLine(maxLength = MaxLineLen + 1)
  if result.len > MaxLineLen:
    fail(431, "line too long")

proc readRequest(client: AsyncSocket): Future[(bool, Request)] {.async.} =
  ## Returns `(false, _)` if the peer closed the connection before sending a
  ## request line.
  var line = await client.readLine()
  while line == "\r\n":          # tolerate stray blank lines between requests
    line = await client.readLine()
  if line.len == 0:
    return (false, Request())

  let parts = line.splitWhitespace()
  if parts.len != 3 or not parts[2].startsWith("HTTP/1."):
    fail(400, "malformed request line")

  var req = Request(meth: parts[0], keepAlive: parts[2] == "HTTP/1.1")
  let target = parts[1]
  let q = target.find({'?', '#'})
  req.path = if q >= 0: target[0 ..< q] else: target

  var contentLength = -1
  var headerCount = 0
  while true:
    let h = await client.readLine()
    if h.len == 0: fail(400, "connection closed in headers")
    if h == "\r\n": break
    inc headerCount
    if headerCount > MaxHeaders: fail(431, "too many headers")
    let colon = h.find(':')
    if colon <= 0: fail(400, "malformed header")
    let name = h[0 ..< colon].strip
    let value = h[colon + 1 .. ^1].strip
    case name.toLowerAscii
    of "content-length":
      var n: int
      try: n = parseInt(value)
      except ValueError: fail(400, "invalid content-length")
      if n < 0 or (contentLength >= 0 and n != contentLength):
        fail(400, "invalid content-length")
      contentLength = n
    of "transfer-encoding":
      fail(501, "transfer-encoding not supported")
    of "connection":
      let v = value.toLowerAscii
      if "close" in v: req.keepAlive = false
      elif "keep-alive" in v: req.keepAlive = true
    else: discard

  if contentLength > MaxBodyLen:
    fail(413, "body too large")
  if contentLength > 0:
    req.body = await client.recv(contentLength)
    if req.body.len != contentLength:
      fail(400, "incomplete body")
  return (true, req)

proc serveClient(client: AsyncSocket) {.async.} =
  try:
    while true:
      var ok: bool
      var req: Request
      try:
        (ok, req) = await client.readRequest()
      except BadRequest as e:
        let resp = Response(status: e.status, body: e.msg, contentType: "text/plain")
        await client.send(resp, keepAlive = false)
        break
      if not ok: break
      let resp = db.route(req.meth, req.path, move req.body)
      await client.send(resp, req.keepAlive)
      if not req.keepAlive: break
  except CatchableError:
    discard                     # peer reset or similar; just drop it
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
  if paramCount() != 1:
    quit("usage: " & getAppFilename().extractFilename & " <port>", QuitFailure)
  let port =
    try: parseInt(paramStr(1))
    except ValueError: -1
  if port notin 1..65535:
    quit("invalid port: " & paramStr(1), QuitFailure)
  waitFor serve(Port(port))

when isMainModule:
  main()
