"""Asyncio-based HTTP/1.1 key-value server.

One request is handled per connection; every response carries an exact
Content-Length and the connection is closed afterwards.
"""

from __future__ import annotations

import argparse
import asyncio
import json
import logging
import re
from dataclasses import dataclass, field
from http import HTTPStatus

log = logging.getLogger("kvhttp")

KEY_RE = re.compile(r"[A-Za-z0-9_-]{1,64}")
MAX_VALUE_BYTES = 1024 * 1024
MAX_HEADER_BYTES = 64 * 1024
READ_TIMEOUT_SECONDS = 30.0
KV_PREFIX = "/kv/"


class HTTPError(Exception):
    def __init__(self, status: HTTPStatus) -> None:
        super().__init__(status.phrase)
        self.status = status


@dataclass(slots=True)
class Response:
    status: HTTPStatus
    body: bytes = b""
    headers: dict[str, str] = field(default_factory=dict)

    def encode(self) -> bytes:
        lines = [f"HTTP/1.1 {self.status.value} {self.status.phrase}"]
        headers = {"Content-Length": str(len(self.body)), "Connection": "close", **self.headers}
        if self.status in (HTTPStatus.NO_CONTENT, HTTPStatus.NOT_MODIFIED):
            del headers["Content-Length"]
        lines.extend(f"{name}: {value}" for name, value in headers.items())
        head = ("\r\n".join(lines) + "\r\n\r\n").encode("latin-1")
        return head + self.body


@dataclass(slots=True)
class Request:
    method: str
    path: str
    headers: dict[str, str]
    body: bytes


class KVStore:
    """In-memory store. Accessed only from the event loop thread, so no locking."""

    def __init__(self) -> None:
        self._data: dict[str, bytes] = {}

    def put(self, key: str, value: bytes) -> bool:
        """Store a value; return True if the key was new."""
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
    def __init__(self, store: KVStore | None = None) -> None:
        self.store = store or KVStore()

    def handle(self, req: Request) -> Response:
        path = req.path
        if path == "/health":
            if req.method == "GET":
                return Response(HTTPStatus.OK, b"ok", {"Content-Type": "text/plain"})
            return self._method_not_allowed("GET")
        if path == "/kv":
            if req.method == "GET":
                body = json.dumps(self.store.keys(), separators=(",", ":")).encode()
                return Response(HTTPStatus.OK, body, {"Content-Type": "application/json"})
            return self._method_not_allowed("GET")
        if path.startswith(KV_PREFIX):
            key = path[len(KV_PREFIX):]
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
                return self._method_not_allowed("GET, PUT, DELETE")

    @staticmethod
    def _method_not_allowed(allow: str) -> Response:
        return Response(HTTPStatus.METHOD_NOT_ALLOWED, headers={"Allow": allow})


async def read_request(reader: asyncio.StreamReader) -> Request:
    try:
        head = await reader.readuntil(b"\r\n\r\n")
    except asyncio.LimitOverrunError as exc:
        raise HTTPError(HTTPStatus.REQUEST_HEADER_FIELDS_TOO_LARGE) from exc

    request_line, *header_lines = head[:-4].decode("latin-1").split("\r\n")
    parts = request_line.split(" ")
    if len(parts) != 3 or not parts[2].startswith("HTTP/"):
        raise HTTPError(HTTPStatus.BAD_REQUEST)
    method, target, _version = parts

    headers: dict[str, str] = {}
    for line in header_lines:
        name, sep, value = line.partition(":")
        if not sep or not name or name != name.strip():
            raise HTTPError(HTTPStatus.BAD_REQUEST)
        headers[name.lower()] = value.strip()

    if "chunked" in headers.get("transfer-encoding", "").lower():
        body = await _read_chunked(reader)
    else:
        raw_length = headers.get("content-length", "0")
        if not raw_length.isdigit():
            raise HTTPError(HTTPStatus.BAD_REQUEST)
        length = int(raw_length)
        if length > MAX_VALUE_BYTES:
            raise HTTPError(HTTPStatus.CONTENT_TOO_LARGE)
        body = await reader.readexactly(length)

    path = target.split("?", 1)[0]
    return Request(method=method, path=path, headers=headers, body=body)


async def _read_chunked(reader: asyncio.StreamReader) -> bytes:
    chunks = bytearray()
    while True:
        size_line = (await reader.readuntil(b"\r\n"))[:-2].split(b";", 1)[0].strip()
        try:
            size = int(size_line, 16)
        except ValueError as exc:
            raise HTTPError(HTTPStatus.BAD_REQUEST) from exc
        if size == 0:
            # Skip trailers up to the terminating blank line.
            while await reader.readuntil(b"\r\n") != b"\r\n":
                pass
            return bytes(chunks)
        if len(chunks) + size > MAX_VALUE_BYTES:
            raise HTTPError(HTTPStatus.CONTENT_TOO_LARGE)
        chunks += await reader.readexactly(size)
        if await reader.readexactly(2) != b"\r\n":
            raise HTTPError(HTTPStatus.BAD_REQUEST)


class Server:
    def __init__(self, app: App) -> None:
        self.app = app

    async def handle_connection(self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
        try:
            try:
                request = await asyncio.wait_for(read_request(reader), READ_TIMEOUT_SECONDS)
                response = self.app.handle(request)
            except HTTPError as exc:
                response = Response(exc.status)
            except (asyncio.IncompleteReadError, TimeoutError, ConnectionError):
                return
            except Exception:
                log.exception("unhandled error while processing request")
                response = Response(HTTPStatus.INTERNAL_SERVER_ERROR)
            writer.write(response.encode())
            await writer.drain()
        except ConnectionError:
            pass
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
        log.info("listening on %s:%d", host, port)
        async with server:
            await server.serve_forever()


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="kvhttp", description="In-memory HTTP key-value server")
    parser.add_argument("port", type=int, help="TCP port to listen on (127.0.0.1)")
    parser.add_argument("--host", default="127.0.0.1")
    args = parser.parse_args(argv)

    logging.basicConfig(level=logging.WARNING, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
    try:
        asyncio.run(Server(App()).serve(args.host, args.port))
    except KeyboardInterrupt:
        pass
    return 0
