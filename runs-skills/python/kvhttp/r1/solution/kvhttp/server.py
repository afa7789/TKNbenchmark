"""Asyncio HTTP/1.1 server exposing an in-memory key-value store.

Routes:
    GET    /health      -> 200 "ok"
    GET    /kv          -> 200 JSON array of all keys, sorted
    PUT    /kv/<key>    -> 201 (created) / 200 (replaced)
    GET    /kv/<key>    -> 200 value / 404
    DELETE /kv/<key>    -> 204 / 404
"""

import argparse
import asyncio
import contextlib
import json
import logging
import re
import signal
from dataclasses import dataclass, field
from http import HTTPStatus

log = logging.getLogger(__name__)

KEY_RE = re.compile(r"[A-Za-z0-9_-]{1,64}")
MAX_VALUE_SIZE = 1024 * 1024
MAX_HEADER_SIZE = 64 * 1024
KEEPALIVE_TIMEOUT = 30.0
KV_PREFIX = "/kv/"


class HTTPError(Exception):
    """A protocol-level failure that maps directly to an error response."""

    def __init__(self, status: HTTPStatus) -> None:
        super().__init__(status.phrase)
        self.status = status


@dataclass(slots=True, frozen=True)
class Request:
    method: str
    path: str
    version: str
    headers: dict[str, str]
    body: bytes

    @property
    def keep_alive(self) -> bool:
        conn = self.headers.get("connection", "").lower()
        if self.version == "HTTP/1.0":
            return conn == "keep-alive"
        return conn != "close"


@dataclass(slots=True, frozen=True)
class Response:
    status: HTTPStatus
    body: bytes = b""
    headers: dict[str, str] = field(default_factory=dict)
    close: bool = False

    def encode(self, *, keep_alive: bool) -> bytes:
        lines = [f"HTTP/1.1 {self.status.value} {self.status.phrase}"]
        lines.extend(f"{name}: {value}" for name, value in self.headers.items())
        # 204 must not carry a body; Content-Length is still well-defined as 0.
        lines.append(f"Content-Length: {len(self.body)}")
        lines.append("Connection: " + ("keep-alive" if keep_alive else "close"))
        head = ("\r\n".join(lines) + "\r\n\r\n").encode("latin-1")
        return head + self.body


def error(status: HTTPStatus, *, close: bool = False) -> Response:
    return Response(status, close=close)


class KVStore:
    """In-memory key-value store. The server runs on a single event loop
    thread, so no locking is needed."""

    def __init__(self) -> None:
        self._data: dict[str, bytes] = {}

    def put(self, key: str, value: bytes) -> bool:
        """Store value; return True if the key was new."""
        created = key not in self._data
        self._data[key] = value
        return created

    def get(self, key: str) -> bytes | None:
        return self._data.get(key)

    def delete(self, key: str) -> bool:
        return self._data.pop(key, None) is not None

    def keys(self) -> list[str]:
        return sorted(self._data)


class App:
    """Routes requests to store operations."""

    def __init__(self, store: KVStore) -> None:
        self.store = store

    def handle(self, req: Request) -> Response:
        path = req.path
        if path == "/health":
            if req.method != "GET":
                return self._not_allowed("GET")
            return Response(
                HTTPStatus.OK, b"ok", {"Content-Type": "text/plain; charset=utf-8"}
            )
        if path == "/kv":
            if req.method != "GET":
                return self._not_allowed("GET")
            body = json.dumps(self.store.keys(), separators=(",", ":")).encode()
            return Response(HTTPStatus.OK, body, {"Content-Type": "application/json"})
        if path.startswith(KV_PREFIX):
            key = path.removeprefix(KV_PREFIX)
            if not KEY_RE.fullmatch(key):
                return error(HTTPStatus.BAD_REQUEST)
            return self._handle_key(req, key)
        return error(HTTPStatus.NOT_FOUND)

    def _handle_key(self, req: Request, key: str) -> Response:
        match req.method:
            case "GET":
                value = self.store.get(key)
                if value is None:
                    return error(HTTPStatus.NOT_FOUND)
                return Response(
                    HTTPStatus.OK,
                    value,
                    {"Content-Type": "application/octet-stream"},
                )
            case "PUT":
                created = self.store.put(key, req.body)
                return Response(HTTPStatus.CREATED if created else HTTPStatus.OK)
            case "DELETE":
                if self.store.delete(key):
                    return Response(HTTPStatus.NO_CONTENT)
                return error(HTTPStatus.NOT_FOUND)
            case _:
                return self._not_allowed("GET, PUT, DELETE")

    @staticmethod
    def _not_allowed(allow: str) -> Response:
        return Response(HTTPStatus.METHOD_NOT_ALLOWED, headers={"Allow": allow})


async def read_request(reader: asyncio.StreamReader) -> Request | None:
    """Read one request; return None on a clean EOF before any bytes."""
    try:
        head = await reader.readuntil(b"\r\n\r\n")
    except asyncio.IncompleteReadError as exc:
        if not exc.partial.strip():
            return None
        raise HTTPError(HTTPStatus.BAD_REQUEST) from exc
    except asyncio.LimitOverrunError as exc:
        raise HTTPError(HTTPStatus.REQUEST_HEADER_FIELDS_TOO_LARGE) from exc

    request_line, *header_lines = head.decode("latin-1").split("\r\n")
    parts = request_line.split(" ")
    if len(parts) != 3 or not parts[2].startswith("HTTP/"):
        raise HTTPError(HTTPStatus.BAD_REQUEST)
    method, target, version = parts

    headers: dict[str, str] = {}
    for line in header_lines:
        if not line:
            continue
        name, sep, value = line.partition(":")
        if not sep or not name or name != name.strip():
            raise HTTPError(HTTPStatus.BAD_REQUEST)
        headers[name.lower()] = value.strip()

    if "chunked" in headers.get("transfer-encoding", "").lower():
        body = await read_chunked(reader)
    else:
        body = await read_fixed(reader, headers.get("content-length"))

    path = target.split("?", 1)[0]
    return Request(method.upper(), path, version, headers, body)


async def read_fixed(reader: asyncio.StreamReader, raw_length: str | None) -> bytes:
    if raw_length is None:
        return b""
    if not raw_length.isdigit():
        raise HTTPError(HTTPStatus.BAD_REQUEST)
    length = int(raw_length)
    if length > MAX_VALUE_SIZE:
        raise HTTPError(HTTPStatus.CONTENT_TOO_LARGE)
    try:
        return await reader.readexactly(length)
    except asyncio.IncompleteReadError as exc:
        raise HTTPError(HTTPStatus.BAD_REQUEST) from exc


async def read_chunked(reader: asyncio.StreamReader) -> bytes:
    body = bytearray()
    try:
        while True:
            size_line = await reader.readuntil(b"\r\n")
            try:
                size = int(size_line.split(b";", 1)[0].strip(), 16)
            except ValueError as exc:
                raise HTTPError(HTTPStatus.BAD_REQUEST) from exc
            if size == 0:
                # Skip trailers up to the terminating blank line.
                while await reader.readuntil(b"\r\n") != b"\r\n":
                    pass
                return bytes(body)
            if len(body) + size > MAX_VALUE_SIZE:
                raise HTTPError(HTTPStatus.CONTENT_TOO_LARGE)
            body += await reader.readexactly(size)
            if await reader.readexactly(2) != b"\r\n":
                raise HTTPError(HTTPStatus.BAD_REQUEST)
    except (asyncio.IncompleteReadError, asyncio.LimitOverrunError) as exc:
        raise HTTPError(HTTPStatus.BAD_REQUEST) from exc


class Server:
    def __init__(self, app: App) -> None:
        self.app = app

    async def handle_connection(
        self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter
    ) -> None:
        try:
            while True:
                try:
                    async with asyncio.timeout(KEEPALIVE_TIMEOUT):
                        req = await read_request(reader)
                except HTTPError as exc:
                    writer.write(error(exc.status).encode(keep_alive=False))
                    await writer.drain()
                    return
                if req is None:
                    return
                resp = self.app.handle(req)
                keep_alive = req.keep_alive and not resp.close
                writer.write(resp.encode(keep_alive=keep_alive))
                await writer.drain()
                if not keep_alive:
                    return
        except TimeoutError, ConnectionError:
            pass
        except Exception:
            log.exception("unhandled error while serving connection")
        finally:
            writer.close()
            with contextlib.suppress(Exception):
                await writer.wait_closed()


async def serve(host: str, port: int) -> None:
    server = Server(App(KVStore()))
    srv = await asyncio.start_server(
        server.handle_connection,
        host,
        port,
        limit=MAX_HEADER_SIZE,
        backlog=1024,
        reuse_address=True,
    )
    loop = asyncio.get_running_loop()
    stop = asyncio.Event()
    for sig in (signal.SIGINT, signal.SIGTERM):
        loop.add_signal_handler(sig, stop.set)
    log.info("listening on %s:%d", host, port)
    async with srv:
        await stop.wait()


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(prog="app", description=__doc__.splitlines()[0])
    parser.add_argument("port", type=int, help="TCP port to listen on")
    parser.add_argument("--host", default="127.0.0.1")
    args = parser.parse_args(argv)
    logging.basicConfig(level=logging.WARNING, format="%(levelname)s %(message)s")
    asyncio.run(serve(args.host, args.port))
    return 0
