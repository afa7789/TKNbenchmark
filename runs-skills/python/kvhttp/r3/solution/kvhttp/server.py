"""A minimal asyncio HTTP/1.1 in-memory key-value server."""

import asyncio
import json
import logging
import re
from dataclasses import dataclass, field
from http import HTTPStatus

log = logging.getLogger(__name__)

KEY_RE = re.compile(r"[A-Za-z0-9_-]{1,64}")
MAX_VALUE_BYTES = 1024 * 1024
MAX_HEADER_BYTES = 64 * 1024
MAX_HEADERS = 100
READ_TIMEOUT_S = 30.0
KV_PREFIX = "/kv/"


class HttpError(Exception):
    """A request problem that maps directly onto an error response."""

    def __init__(self, status: HTTPStatus) -> None:
        super().__init__(status.phrase)
        self.status = status


@dataclass(slots=True, kw_only=True)
class Request:
    method: str
    path: str
    version: str
    headers: dict[str, str]
    body: bytes = b""

    @property
    def keep_alive(self) -> bool:
        conn = self.headers.get("connection", "").lower()
        if self.version == "HTTP/1.0":
            return conn == "keep-alive"
        return conn != "close"


@dataclass(slots=True, kw_only=True)
class Response:
    status: HTTPStatus
    body: bytes = b""
    headers: dict[str, str] = field(default_factory=dict)

    def encode(self, *, keep_alive: bool) -> bytes:
        lines = [f"HTTP/1.1 {self.status.value} {self.status.phrase}"]
        lines.extend(f"{name}: {value}" for name, value in self.headers.items())
        # 204 must not carry a body; Content-Length is omitted for it per RFC 9110.
        if self.status is not HTTPStatus.NO_CONTENT:
            lines.append(f"Content-Length: {len(self.body)}")
        lines.append(f"Connection: {'keep-alive' if keep_alive else 'close'}")
        head = ("\r\n".join(lines) + "\r\n\r\n").encode("latin-1")
        return head + self.body


def _text(status: HTTPStatus, text: str | None = None) -> Response:
    body = (status.phrase if text is None else text).encode()
    return Response(
        status=status,
        body=body,
        headers={"Content-Type": "text/plain; charset=utf-8"},
    )


class KeyValueStore:
    """In-memory store; all access happens on the event loop thread."""

    def __init__(self) -> None:
        self._data: dict[str, bytes] = {}

    def get(self, key: str) -> bytes | None:
        return self._data.get(key)

    def put(self, key: str, value: bytes) -> bool:
        """Store a value; return True if the key was newly created."""
        created = key not in self._data
        self._data[key] = value
        return created

    def delete(self, key: str) -> bool:
        return self._data.pop(key, None) is not None

    def keys(self) -> list[str]:
        return sorted(self._data)


class App:
    def __init__(self, store: KeyValueStore | None = None) -> None:
        self.store = store or KeyValueStore()

    def handle(self, req: Request) -> Response:
        path = req.path
        if path == "/health":
            if req.method != "GET":
                return _method_not_allowed("GET")
            return _text(HTTPStatus.OK, "ok")
        if path == "/kv":
            if req.method != "GET":
                return _method_not_allowed("GET")
            return Response(
                status=HTTPStatus.OK,
                body=json.dumps(self.store.keys(), separators=(",", ":")).encode(),
                headers={"Content-Type": "application/json"},
            )
        if path.startswith(KV_PREFIX):
            key = path.removeprefix(KV_PREFIX)
            if not KEY_RE.fullmatch(key):
                return _text(HTTPStatus.BAD_REQUEST)
            return self._handle_key(req, key)
        return _text(HTTPStatus.NOT_FOUND)

    def _handle_key(self, req: Request, key: str) -> Response:
        match req.method:
            case "GET":
                value = self.store.get(key)
                if value is None:
                    return _text(HTTPStatus.NOT_FOUND)
                return Response(
                    status=HTTPStatus.OK,
                    body=value,
                    headers={"Content-Type": "application/octet-stream"},
                )
            case "PUT":
                created = self.store.put(key, req.body)
                return Response(
                    status=HTTPStatus.CREATED if created else HTTPStatus.OK
                )
            case "DELETE":
                if self.store.delete(key):
                    return Response(status=HTTPStatus.NO_CONTENT)
                return _text(HTTPStatus.NOT_FOUND)
            case _:
                return _method_not_allowed("GET, PUT, DELETE")


def _method_not_allowed(allow: str) -> Response:
    resp = _text(HTTPStatus.METHOD_NOT_ALLOWED)
    resp.headers["Allow"] = allow
    return resp


async def read_request(reader: asyncio.StreamReader) -> Request | None:
    """Read one request; return None on a clean EOF before any bytes."""
    try:
        head = await reader.readuntil(b"\r\n\r\n")
    except asyncio.IncompleteReadError as exc:
        if not exc.partial.strip():
            return None
        raise HttpError(HTTPStatus.BAD_REQUEST) from exc
    except asyncio.LimitOverrunError as exc:
        raise HttpError(HTTPStatus.REQUEST_HEADER_FIELDS_TOO_LARGE) from exc

    lines = head.decode("latin-1").split("\r\n")
    try:
        method, target, version = lines[0].split(" ")
    except ValueError as exc:
        raise HttpError(HTTPStatus.BAD_REQUEST) from exc
    if not version.startswith("HTTP/1."):
        raise HttpError(HTTPStatus.HTTP_VERSION_NOT_SUPPORTED)

    headers: dict[str, str] = {}
    header_lines = [line for line in lines[1:] if line]
    if len(header_lines) > MAX_HEADERS:
        raise HttpError(HTTPStatus.REQUEST_HEADER_FIELDS_TOO_LARGE)
    for line in header_lines:
        name, sep, value = line.partition(":")
        if not sep or not name or name != name.strip():
            raise HttpError(HTTPStatus.BAD_REQUEST)
        headers[name.lower()] = value.strip()

    path = target.split("?", 1)[0]
    body = await _read_body(reader, headers)
    return Request(method=method, path=path, version=version, headers=headers, body=body)


async def _read_body(reader: asyncio.StreamReader, headers: dict[str, str]) -> bytes:
    if "chunked" in headers.get("transfer-encoding", "").lower():
        return await _read_chunked(reader)
    raw_length = headers.get("content-length")
    if raw_length is None:
        return b""
    if not raw_length.isdigit():
        raise HttpError(HTTPStatus.BAD_REQUEST)
    length = int(raw_length)
    if length > MAX_VALUE_BYTES:
        raise HttpError(HTTPStatus.CONTENT_TOO_LARGE)
    try:
        return await reader.readexactly(length)
    except asyncio.IncompleteReadError as exc:
        raise HttpError(HTTPStatus.BAD_REQUEST) from exc


async def _read_chunked(reader: asyncio.StreamReader) -> bytes:
    body = bytearray()
    try:
        while True:
            size_line = await reader.readuntil(b"\r\n")
            try:
                size = int(size_line.split(b";", 1)[0].strip(), 16)
            except ValueError as exc:
                raise HttpError(HTTPStatus.BAD_REQUEST) from exc
            if size == 0:
                # Discard trailers up to the terminating blank line.
                while await reader.readuntil(b"\r\n") != b"\r\n":
                    pass
                return bytes(body)
            if len(body) + size > MAX_VALUE_BYTES:
                raise HttpError(HTTPStatus.CONTENT_TOO_LARGE)
            body += await reader.readexactly(size)
            if await reader.readexactly(2) != b"\r\n":
                raise HttpError(HTTPStatus.BAD_REQUEST)
    except (asyncio.IncompleteReadError, asyncio.LimitOverrunError) as exc:
        raise HttpError(HTTPStatus.BAD_REQUEST) from exc


class Server:
    def __init__(self, app: App) -> None:
        self.app = app

    async def handle_connection(
        self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter
    ) -> None:
        try:
            while True:
                try:
                    async with asyncio.timeout(READ_TIMEOUT_S):
                        req = await read_request(reader)
                except HttpError as exc:
                    writer.write(_text(exc.status).encode(keep_alive=False))
                    await writer.drain()
                    return
                if req is None:
                    return
                resp = self.app.handle(req)
                keep_alive = req.keep_alive
                writer.write(resp.encode(keep_alive=keep_alive))
                await writer.drain()
                if not keep_alive:
                    return
        except (TimeoutError, ConnectionError):
            pass
        except Exception:
            log.exception("unhandled error while serving connection")
        finally:
            writer.close()
            try:
                await writer.wait_closed()
            except ConnectionError:
                pass


async def serve(host: str, port: int) -> None:
    server = Server(App())
    srv = await asyncio.start_server(
        server.handle_connection,
        host,
        port,
        limit=MAX_HEADER_BYTES,
        backlog=1024,
        reuse_address=True,
    )
    log.info("listening on %s:%d", host, port)
    async with srv:
        await srv.serve_forever()
