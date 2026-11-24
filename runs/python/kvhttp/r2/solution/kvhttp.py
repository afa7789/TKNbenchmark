"""kvhttp: a minimal in-memory HTTP/1.1 key-value server (see SPEC.md)."""

from __future__ import annotations

import asyncio
import json
import logging
import re
import sys
from dataclasses import dataclass, field
from http import HTTPStatus

MAX_VALUE_SIZE = 1024 * 1024
MAX_HEADER_SIZE = 64 * 1024
KEY_RE = re.compile(r"[A-Za-z0-9_-]{1,64}")
KV_PREFIX = "/kv/"

log = logging.getLogger("kvhttp")


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

    def serialize(self) -> bytes:
        lines = [f"HTTP/1.1 {self.status.value} {self.status.phrase}"]
        headers = {"Connection": "close", **self.headers}
        if self.body and "Content-Type" not in headers:
            headers["Content-Type"] = "application/octet-stream"
        headers["Content-Length"] = str(len(self.body))
        lines.extend(f"{name}: {value}" for name, value in headers.items())
        head = "\r\n".join(lines).encode("latin-1") + b"\r\n\r\n"
        return head + self.body


class Store:
    """In-memory key-value store. All access happens on the event loop thread."""

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
    def __init__(self, store: Store) -> None:
        self.store = store

    def handle(self, req: Request) -> Response:
        path = req.path
        if path == "/health":
            if req.method != "GET":
                return Response(HTTPStatus.METHOD_NOT_ALLOWED, headers={"Allow": "GET"})
            return Response(HTTPStatus.OK, b"ok", {"Content-Type": "text/plain"})
        if path == "/kv":
            if req.method != "GET":
                return Response(HTTPStatus.METHOD_NOT_ALLOWED, headers={"Allow": "GET"})
            body = json.dumps(self.store.keys(), separators=(",", ":")).encode()
            return Response(HTTPStatus.OK, body, {"Content-Type": "application/json"})
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
                return Response(HTTPStatus.OK, value)
            case "PUT":
                created = self.store.put(key, req.body)
                return Response(HTTPStatus.CREATED if created else HTTPStatus.OK)
            case "DELETE":
                if self.store.delete(key):
                    return Response(HTTPStatus.NO_CONTENT)
                return Response(HTTPStatus.NOT_FOUND)
            case _:
                return Response(
                    HTTPStatus.METHOD_NOT_ALLOWED, headers={"Allow": "GET, PUT, DELETE"}
                )


async def read_request(reader: asyncio.StreamReader) -> Request | None:
    try:
        head = await reader.readuntil(b"\r\n\r\n")
    except asyncio.IncompleteReadError as exc:
        if not exc.partial.strip():
            return None  # client closed without sending anything
        raise HttpError(HTTPStatus.BAD_REQUEST) from exc
    except asyncio.LimitOverrunError as exc:
        raise HttpError(HTTPStatus.REQUEST_HEADER_FIELDS_TOO_LARGE) from exc

    try:
        request_line, *header_lines = head.decode("latin-1").split("\r\n")
        method, target, _version = request_line.split(" ")
    except ValueError as exc:
        raise HttpError(HTTPStatus.BAD_REQUEST) from exc

    headers: dict[str, str] = {}
    for line in header_lines:
        if not line:
            continue
        name, sep, value = line.partition(":")
        if not sep:
            raise HttpError(HTTPStatus.BAD_REQUEST)
        headers[name.strip().lower()] = value.strip()

    path = target.split("?", 1)[0]
    body = await read_body(reader, headers)
    return Request(method, path, headers, body)


async def read_body(reader: asyncio.StreamReader, headers: dict[str, str]) -> bytes:
    if "chunked" in headers.get("transfer-encoding", "").lower():
        return await read_chunked(reader)
    raw_length = headers.get("content-length")
    if raw_length is None:
        return b""
    if not raw_length.isdigit():
        raise HttpError(HTTPStatus.BAD_REQUEST)
    length = int(raw_length)
    try:
        if length > MAX_VALUE_SIZE:
            # Drain the body so the client reliably receives the error response.
            await discard(reader, length)
            raise HttpError(HTTPStatus.CONTENT_TOO_LARGE)
        return await reader.readexactly(length)
    except asyncio.IncompleteReadError as exc:
        raise HttpError(HTTPStatus.BAD_REQUEST) from exc


async def discard(reader: asyncio.StreamReader, length: int) -> None:
    while length > 0:
        chunk = await reader.read(min(length, 64 * 1024))
        if not chunk:
            raise asyncio.IncompleteReadError(b"", length)
        length -= len(chunk)


async def read_chunked(reader: asyncio.StreamReader) -> bytes:
    body = bytearray()
    try:
        while True:
            size_line = await reader.readuntil(b"\r\n")
            size = int(size_line.split(b";", 1)[0].strip(), 16)
            if size == 0:
                # Consume optional trailers up to the terminating blank line.
                while (await reader.readuntil(b"\r\n")) != b"\r\n":
                    pass
                return bytes(body)
            if len(body) + size > MAX_VALUE_SIZE:
                raise HttpError(HTTPStatus.CONTENT_TOO_LARGE)
            body += await reader.readexactly(size)
            await reader.readexactly(2)
    except (ValueError, asyncio.IncompleteReadError, asyncio.LimitOverrunError) as exc:
        raise HttpError(HTTPStatus.BAD_REQUEST) from exc


class Server:
    def __init__(self, app: App) -> None:
        self.app = app

    async def handle_connection(
        self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter
    ) -> None:
        try:
            try:
                request = await read_request(reader)
                if request is None:
                    return
                response = self.app.handle(request)
            except HttpError as exc:
                response = Response(exc.status)
            writer.write(response.serialize())
            await writer.drain()
        except (ConnectionError, OSError):
            pass
        except Exception:
            log.exception("unhandled error while serving request")
        finally:
            writer.close()
            try:
                await writer.wait_closed()
            except (ConnectionError, OSError):
                pass

    async def serve(self, host: str, port: int) -> None:
        server = await asyncio.start_server(
            self.handle_connection, host, port, limit=MAX_HEADER_SIZE, backlog=1024
        )
        async with server:
            await server.serve_forever()


def main(argv: list[str]) -> int:
    if len(argv) != 2 or not argv[1].isdigit():
        print(f"usage: {argv[0]} <port>", file=sys.stderr)
        return 2
    logging.basicConfig(level=logging.WARNING, format="%(levelname)s %(name)s: %(message)s")
    server = Server(App(Store()))
    try:
        asyncio.run(server.serve("127.0.0.1", int(argv[1])))
    except KeyboardInterrupt:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
