"""kvhttp: an in-memory HTTP/1.1 key-value server.

Usage: python3 kvhttp.py <port>

Serves on 127.0.0.1:<port>, one request per connection, until killed.
"""

import asyncio
import json
import logging
import re
import signal
import sys
from dataclasses import dataclass, field
from http import HTTPStatus

log = logging.getLogger("kvhttp")

HOST = "127.0.0.1"
MAX_VALUE_BYTES = 1024 * 1024
MAX_HEAD_BYTES = 64 * 1024
HEADER_TIMEOUT_S = 30.0
BACKLOG = 1024

KEY_RE = re.compile(r"[A-Za-z0-9_-]{1,64}")
KV_PREFIX = "/kv/"


@dataclass(slots=True)
class Request:
    method: str
    path: str
    headers: dict[str, str]
    body: bytes = b""


@dataclass(slots=True)
class Response:
    status: HTTPStatus
    body: bytes = b""
    headers: dict[str, str] = field(default_factory=dict)

    def encode(self) -> bytes:
        lines = [f"HTTP/1.1 {self.status.value} {self.status.phrase}"]
        headers = dict(self.headers)
        # RFC 9110: no Content-Length on 204; the connection closes anyway.
        if self.status is not HTTPStatus.NO_CONTENT:
            headers["Content-Length"] = str(len(self.body))
        headers["Connection"] = "close"
        lines.extend(f"{name}: {value}" for name, value in headers.items())
        head = ("\r\n".join(lines) + "\r\n\r\n").encode("latin-1")
        return head + self.body


class BadRequest(Exception):
    """The request could not be parsed; reply with the given status."""

    def __init__(self, status: HTTPStatus) -> None:
        super().__init__(status.phrase)
        self.status = status


def text(status: HTTPStatus, body: str = "") -> Response:
    headers = {"Content-Type": "text/plain; charset=utf-8"} if body else {}
    return Response(status, body.encode(), headers)


class KVStore:
    """The route handlers over an in-memory dict (event-loop confined)."""

    def __init__(self) -> None:
        self._data: dict[str, bytes] = {}

    def handle(self, req: Request) -> Response:
        path = req.path
        if path == "/health":
            if req.method == "GET":
                return text(HTTPStatus.OK, "ok")
            return self._not_allowed("GET")
        if path == "/kv":
            if req.method == "GET":
                body = json.dumps(sorted(self._data), separators=(",", ":"))
                return Response(
                    HTTPStatus.OK,
                    body.encode(),
                    {"Content-Type": "application/json"},
                )
            return self._not_allowed("GET")
        if path.startswith(KV_PREFIX):
            key = path.removeprefix(KV_PREFIX)
            if not KEY_RE.fullmatch(key):
                return text(HTTPStatus.BAD_REQUEST, "invalid key")
            return self._handle_key(req, key)
        return text(HTTPStatus.NOT_FOUND, "not found")

    def _handle_key(self, req: Request, key: str) -> Response:
        match req.method:
            case "GET":
                value = self._data.get(key)
                if value is None:
                    return text(HTTPStatus.NOT_FOUND, "not found")
                return Response(
                    HTTPStatus.OK,
                    value,
                    {"Content-Type": "application/octet-stream"},
                )
            case "PUT":
                existed = key in self._data
                self._data[key] = req.body
                return Response(HTTPStatus.OK if existed else HTTPStatus.CREATED)
            case "DELETE":
                if self._data.pop(key, None) is None:
                    return text(HTTPStatus.NOT_FOUND, "not found")
                return Response(HTTPStatus.NO_CONTENT)
            case _:
                return self._not_allowed("GET, PUT, DELETE")

    @staticmethod
    def _not_allowed(allow: str) -> Response:
        resp = text(HTTPStatus.METHOD_NOT_ALLOWED, "method not allowed")
        resp.headers["Allow"] = allow
        return resp


def parse_head(head: bytes) -> tuple[str, str, dict[str, str]]:
    try:
        lines = head.decode("latin-1").split("\r\n")
        method, target, version = lines[0].split(" ")
    except ValueError:
        raise BadRequest(HTTPStatus.BAD_REQUEST) from None
    if not version.startswith("HTTP/") or not method.isalpha():
        raise BadRequest(HTTPStatus.BAD_REQUEST)
    headers: dict[str, str] = {}
    for line in lines[1:]:
        if not line:
            continue
        name, sep, value = line.partition(":")
        if not sep or not name or name != name.strip():
            raise BadRequest(HTTPStatus.BAD_REQUEST)
        headers[name.lower()] = value.strip()
    path = target.partition("?")[0]
    return method, path, headers


def content_length(headers: dict[str, str]) -> int:
    raw = headers.get("content-length")
    if raw is None:
        if "transfer-encoding" in headers:
            raise BadRequest(HTTPStatus.LENGTH_REQUIRED)
        return 0
    if not raw.isdigit():
        raise BadRequest(HTTPStatus.BAD_REQUEST)
    length = int(raw)
    if length > MAX_VALUE_BYTES:
        raise BadRequest(HTTPStatus.CONTENT_TOO_LARGE)
    return length


async def read_request(reader: asyncio.StreamReader) -> Request:
    try:
        async with asyncio.timeout(HEADER_TIMEOUT_S):
            head = await reader.readuntil(b"\r\n\r\n")
    except asyncio.LimitOverrunError:
        raise BadRequest(HTTPStatus.REQUEST_HEADER_FIELDS_TOO_LARGE) from None
    method, path, headers = parse_head(head[:-4])
    length = content_length(headers)
    body = await reader.readexactly(length) if length else b""
    return Request(method, path, headers, body)


class Server:
    def __init__(self, store: KVStore) -> None:
        self.store = store

    async def handle_connection(
        self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter
    ) -> None:
        try:
            try:
                req = await read_request(reader)
            except BadRequest as exc:
                resp = text(exc.status, exc.status.phrase)
            else:
                resp = self.store.handle(req)
            writer.write(resp.encode())
            await writer.drain()
        except (asyncio.IncompleteReadError, TimeoutError, ConnectionError):
            pass  # client went away or stalled; nothing useful to send
        except Exception:
            log.exception("unhandled error while serving request")
        finally:
            writer.close()
            try:
                await writer.wait_closed()
            except ConnectionError:
                pass


async def serve(port: int) -> None:
    server = Server(KVStore())
    srv = await asyncio.start_server(
        server.handle_connection,
        HOST,
        port,
        backlog=BACKLOG,
        limit=MAX_HEAD_BYTES,
        reuse_address=True,
    )
    loop = asyncio.get_running_loop()
    stop = asyncio.Event()
    for sig in (signal.SIGINT, signal.SIGTERM):
        loop.add_signal_handler(sig, stop.set)
    log.info("listening on %s:%d", HOST, port)
    async with srv:
        await stop.wait()


def parse_port(argv: list[str]) -> int:
    if len(argv) != 2:
        raise SystemExit(f"usage: {argv[0]} <port>")
    try:
        port = int(argv[1])
    except ValueError:
        raise SystemExit(f"invalid port: {argv[1]!r}") from None
    if not 0 < port < 65536:
        raise SystemExit(f"port out of range: {port}")
    return port


def main() -> None:
    logging.basicConfig(level=logging.WARNING, format="%(levelname)s %(message)s")
    asyncio.run(serve(parse_port(sys.argv)))


if __name__ == "__main__":
    main()
