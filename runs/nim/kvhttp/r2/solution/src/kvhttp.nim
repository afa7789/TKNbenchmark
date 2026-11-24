## kvhttp: an in-memory HTTP/1.1 key-value server.
##
## Usage: `kvhttp <port>` — listens on 127.0.0.1:<port> until killed.
## One request is served per connection; every response carries an exact
## Content-Length and the connection is closed after it.

import std/[asyncdispatch, asyncnet, httpcore, net, os, posix, strutils]
import kvhttp/router

const
  MaxLineLen = 8 * 1024        ## Request line / single header line limit.
  MaxHeaders = 100
  MaxBodyLen = MaxValueLen + 64 * 1024 ## Hard cap on bytes we accept in a body.
  RequestTimeoutMs = 30_000
  ListenBacklog = 1024

type
  HttpError = object of CatchableError
    code: HttpCode

  Request = object
    meth, path, body: string

var store: Store

proc httpError(code: HttpCode; msg = ""): ref HttpError =
  (ref HttpError)(code: code, msg: msg)

proc readLineStrict(client: AsyncSocket): Future[string] {.async.} =
  ## Reads one CRLF-terminated line; raises on disconnect or overlong lines.
  let line = await client.recvLine(maxLength = MaxLineLen + 1)
  if line.len == 0:
    raise newException(IOError, "client disconnected")
  if line.len > MaxLineLen:
    raise httpError(Http431, "line too long")
  return line

proc readExact(client: AsyncSocket; n: int): Future[string] {.async.} =
  result = await client.recv(n)
  if result.len != n:
    raise newException(IOError, "client disconnected mid-body")

proc readChunked(client: AsyncSocket): Future[string] {.async.} =
  while true:
    let sizeField = (await client.readLineStrict()).split(';', maxsplit = 1)[0].strip
    var size: int
    try:
      size = parseHexInt(sizeField)
    except ValueError:
      raise httpError(Http400, "bad chunk size")
    if size < 0 or size > MaxBodyLen - result.len:
      raise httpError(Http413)
    if size == 0:
      break
    result.add await client.readExact(size)
    discard await client.readExact(2) # CRLF after chunk data
  # Discard optional trailers up to the terminating empty line.
  while (await client.readLineStrict()) != "\r\n":
    discard

proc readRequest(client: AsyncSocket): Future[Request] {.async.} =
  var line = await client.readLineStrict()
  while line == "\r\n": # tolerate stray CRLFs before the request line
    line = await client.readLineStrict()
  let parts = line.splitWhitespace()
  if parts.len != 3 or not parts[2].startsWith("HTTP/1."):
    raise httpError(Http400, "malformed request line")
  result.meth = parts[0]
  result.path = parts[1]

  let headers = newHttpHeaders()
  while true:
    let h = await client.readLineStrict()
    if h == "\r\n":
      break
    if headers.len >= MaxHeaders:
      raise httpError(Http431)
    let colon = h.find(':')
    if colon <= 0:
      raise httpError(Http400, "malformed header")
    headers.add(h[0 ..< colon], h[colon + 1 .. ^1].strip)

  if "chunked" in headers.getOrDefault("Transfer-Encoding").toString.toLowerAscii:
    result.body = await client.readChunked()
  elif headers.hasKey("Content-Length"):
    var length: int
    try:
      length = parseInt(headers["Content-Length"].strip)
    except ValueError:
      raise httpError(Http400, "bad Content-Length")
    if length < 0:
      raise httpError(Http400, "bad Content-Length")
    if length > MaxBodyLen:
      raise httpError(Http413)
    if length > 0:
      result.body = await client.readExact(length)

proc send(client: AsyncSocket; resp: Response) {.async.} =
  var msg = "HTTP/1.1 " & $resp.code & "\r\n"
  msg.add "Content-Length: " & $resp.body.len & "\r\n"
  if resp.contentType.len > 0:
    msg.add "Content-Type: " & resp.contentType & "\r\n"
  msg.add "Connection: close\r\n\r\n"
  msg.add resp.body
  await client.send(msg)

proc serveClient(client: AsyncSocket) {.async.} =
  try:
    let reading = client.readRequest()
    if not await reading.withTimeout(RequestTimeoutMs):
      await client.send(Response(code: Http408))
    elif reading.failed:
      let err = reading.readError()
      if err of HttpError:
        await client.send(Response(code: (ref HttpError)(err).code))
    else:
      let req = reading.read()
      await client.send(store.route(req.meth, req.path, req.body))
  except CatchableError:
    discard # client went away; nothing useful to report
  finally:
    client.close()

proc serve(port: Port) {.async.} =
  let server = newAsyncSocket()
  server.setSockOpt(OptReuseAddr, true)
  server.bindAddr(port, "127.0.0.1")
  server.listen(ListenBacklog)
  while true:
    try:
      let client = await server.accept()
      asyncCheck serveClient(client)
    except OSError as e:
      # e.g. EMFILE: back off briefly instead of spinning.
      stderr.writeLine "accept failed: ", e.msg
      await sleepAsync(10)

proc main() =
  if paramCount() != 1:
    quit "usage: " & getAppFilename().extractFilename & " <port>", QuitFailure
  let port =
    try: parseInt(paramStr(1))
    except ValueError: -1
  if port notin 1..65535:
    quit "invalid port: " & paramStr(1), QuitFailure
  signal(SIGPIPE, SIG_IGN)
  waitFor serve(Port(port))

when isMainModule:
  main()
