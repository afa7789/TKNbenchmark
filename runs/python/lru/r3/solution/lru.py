"""Simulate an LRU cache driven by commands read from standard input."""

import sys
from collections import OrderedDict

NULL = b"NULL"


def run(data: bytes) -> bytes:
    """Execute the command stream in ``data`` and return the output bytes."""
    lines = data.split(b"\n")
    if not lines or not lines[0].strip():
        return b""
    capacity = int(lines[0])

    cache: OrderedDict[bytes, bytes] = OrderedDict()
    move_to_end = cache.move_to_end
    popitem = cache.popitem
    get = cache.get
    pop = cache.pop
    out: list[bytes] = []
    emit = out.append

    for line in lines[1:]:
        parts = line.split()
        if not parts:
            continue
        cmd = parts[0]
        if cmd == b"GET":
            key = parts[1]
            value = get(key)
            if value is None:
                emit(NULL)
            else:
                move_to_end(key)
                emit(value)
        elif cmd == b"SET":
            key = parts[1]
            if key in cache:
                move_to_end(key)
            cache[key] = parts[2]
            if len(cache) > capacity:
                popitem(last=False)
        elif cmd == b"DEL":
            emit(b"0" if pop(parts[1], None) is None else b"1")
        elif cmd == b"SIZE":
            emit(str(len(cache)).encode())

    if not out:
        return b""
    out.append(b"")
    return b"\n".join(out)


def main() -> int:
    sys.stdout.buffer.write(run(sys.stdin.buffer.read()))
    sys.stdout.buffer.flush()
    return 0


if __name__ == "__main__":
    sys.exit(main())
