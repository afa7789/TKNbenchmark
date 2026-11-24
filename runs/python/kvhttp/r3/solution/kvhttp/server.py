"""Asyncio-based HTTP/1.1 key-value server.

Handles one request per connection and always closes the connection after
responding, which is all the protocol contract requires.
"""

from __future__ import annotations

import asyncio
import json
import logging
import re
import sys
from dataclasses import dataclass, field
from http import HTTPStatus

log = logging.getLogger("kvhttp")

KEY_RE = re.compile(r"[A-Za-z0-9_-]{1,64}")
MAX_VALUE_BYTES = 1024 * 1024
MAX_HEADER_BYTES = 64 * 1024
READ_TIMEOUT_S = 30.0


class HttpError(Exception):
    def __init__(self, status: HTTPStatus) -> None:
        super().__init__(status.phrase)
        self.status = status


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
        headers = {**self.headers, "Content-Length": str(len(self.body)), "Connection": "close"}
        lines.extend(f"{name}: {value}" for name, value in headers.items())
        head = ("\r\n".join(lines) + "\r\n\r\n").encode("latin-1")
        return head + self.body


class Store:
    """In-memory key-value store.

    All access happens on the event loop thread, so no locking is required.
    """

    def __init__(self) -> None:
        self._data: dict[str, bytes] = {}

    def put(self, key: str, value: bytes) -> bool:
        """Store a value; return True if the key was newly created."""
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
    def __init__(self, store: Store | None = None) -> None:
        self.store = store or Store()

    def handle(self, req: Request) -> Response:
        path = req.path
        if path == "/health":
            if req.method != "GET":
                return _method_not_allowed("GET")
            return Response(HTTPStatus.OK, b"ok", {"Content-Type": "text/plain; charset=utf-8"})
        if path == "/kv":
            if req.method != "GET":
                return _method_not_allowed("GET")
            body = json.dumps(self.store.keys(), separators=(",", ":")).encode()
            return Response(HTTPStatus.OK, body, {"Content-Type": "application/json"})
        if path.startswith("/kv/"):
            key = path.removeprefix("/kv/")
            if not KEY_RE.fullmatch(key):
                return Response(HTTPStatus.BAD_REQUEST)
            return self._handle_key(req, key)
        return Response(HTTPStatus.NOT_FOUND)

    def _handle_key(self, req: Request, key: str) -> Response:
        match req.method:
            case "GET":
                value = self.store.get(key)
                if value is None:
                    return Response(HTTPStatus.NOT_FOUND)
                return Response(HTTPStatus.OK, value, {"Content-Type": "application/octet-stream"})
            case "PUT":
                created = self.store.put(key, req.body)
                return Response(HTTPStatus.CREATED if created else HTTPStatus.OK)
            case "DELETE":
                if self.store.delete(key):
                    return Response(HTTPStatus.NO_CONTENT)
                return Response(HTTPStatus.NOT_FOUND)
            case _:
                return _method_not_allowed("GET, PUT, DELETE")


def _method_not_allowed(allow: str) -> Response:
    return Response(HTTPStatus.METHOD_NOT_ALLOWED, headers={"Allow": allow})


async def read_request(reader: asyncio.StreamReader) -> Request:
    try:
        head = await reader.readuntil(b"\r\n\r\n")
    except asyncio.LimitOverrunError as exc:
        raise HttpError(HTTPStatus.REQUEST_HEADER_FIELDS_TOO_LARGE) from exc

    request_line, *header_lines = head[:-4].decode("latin-1").split("\r\n")
    parts = request_line.split(" ")
    if len(parts) != 3 or not parts[2].startswith("HTTP/"):
        raise HttpError(HTTPStatus.BAD_REQUEST)
    method, target, _version = parts

    headers: dict[str, str] = {}
    for line in header_lines:
        name, sep, value = line.partition(":")
        if not sep or not name or name != name.strip():
            raise HttpError(HTTPStatus.BAD_REQUEST)
        headers[name.lower()] = value.strip()

    path = target.split("?", 1)[0]
    if "transfer-encoding" in headers:
        if headers["transfer-encoding"].lower() != "chunked":
            raise HttpError(HTTPStatus.NOT_IMPLEMENTED)
        body = await _read_chunked(reader)
    else:
        body = await _read_fixed(reader, headers.get("content-length"))
    return Request(method, path, headers, body)


async def _read_fixed(reader: asyncio.StreamReader, raw_length: str | None) -> bytes:
    if raw_length is None:
        return b""
    if not raw_length.isdigit():
        raise HttpError(HTTPStatus.BAD_REQUEST)
    length = int(raw_length)
    if length > MAX_VALUE_BYTES:
        raise HttpError(HTTPStatus.CONTENT_TOO_LARGE)
    return await reader.readexactly(length)


async def _read_chunked(reader: asyncio.StreamReader) -> bytes:
    chunks: list[bytes] = []
    total = 0
    while True:
        size_line = (await reader.readuntil(b"\r\n")).split(b";", 1)[0].strip()
        try:
            size = int(size_line, 16)
        except ValueError as exc:
            raise HttpError(HTTPStatus.BAD_REQUEST) from exc
        if size == 0:
            # Discard trailers up to the terminating blank line.
            while await reader.readuntil(b"\r\n") != b"\r\n":
                pass
            return b"".join(chunks)
        total += size
        if total > MAX_VALUE_BYTES:
            raise HttpError(HTTPStatus.CONTENT_TOO_LARGE)
        chunks.append(await reader.readexactly(size))
        if await reader.readexactly(2) != b"\r\n":
            raise HttpError(HTTPStatus.BAD_REQUEST)


class Server:
    def __init__(self, app: App) -> None:
        self.app = app

    async def handle_connection(
        self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter
    ) -> None:
        try:
            try:
                req = await asyncio.wait_for(read_request(reader), READ_TIMEOUT_S)
                resp = self.app.handle(req)
            except HttpError as exc:
                resp = Response(exc.status)
            writer.write(resp.encode())
            await writer.drain()
        except (asyncio.IncompleteReadError, TimeoutError, ConnectionError):
            pass  # Client went away or stalled; nothing useful to send.
        except Exception:
            log.exception("unhandled error while serving request")
        finally:
            writer.close()
            try:
                await writer.wait_closed()
            except ConnectionError:
                pass

    async def serve(self, host: str, port: int) -> None:
        server = await asyncio.start_server(
            self.handle_connection, host, port, limit=MAX_HEADER_BYTES, backlog=1024
        )
        async with server:
            await server.serve_forever()


def main(argv: list[str] | None = None) -> int:
    args = sys.argv[1:] if argv is None else argv
    if len(args) != 1 or not args[0].isdigit() or not 0 < int(args[0]) < 65536:
        print("usage: app <port>", file=sys.stderr)
        return 2
    logging.basicConfig(level=logging.WARNING, format="%(levelname)s %(name)s: %(message)s")
    try:
        asyncio.run(Server(App()).serve("127.0.0.1", int(args[0])))
    except KeyboardInterrupt:
        pass
    return 0
