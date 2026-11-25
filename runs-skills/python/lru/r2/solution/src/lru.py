"""LRU cache simulator: reads a capacity and commands from stdin, writes results."""

import sys
from collections import OrderedDict

NULL = b"NULL"
SIZE = b"SIZE"


def run(data: bytes) -> bytes:
    """Execute the command stream in ``data`` and return the combined output."""
    lines = data.split(b"\n")
    if not lines[0].strip():
        return b""
    capacity = int(lines[0])
    cache: OrderedDict[bytes, bytes] = OrderedDict()
    move_to_end = cache.move_to_end
    popitem = cache.popitem
    out: list[bytes] = []
    emit = out.append

    for line in lines[1:]:
        if not line:
            continue
        if line[-1] == 13:  # tolerate CRLF line endings
            line = line[:-1]
        parts = line.split(b" ")
        op = parts[0]
        if op == b"SET":
            key = parts[1]
            if key in cache:
                move_to_end(key)
                cache[key] = parts[2]
            else:
                cache[key] = parts[2]
                if len(cache) > capacity:
                    popitem(last=False)
        elif op == b"GET":
            key = parts[1]
            value = cache.get(key)
            if value is None:
                emit(NULL)
            else:
                move_to_end(key)
                emit(value)
        elif op == b"DEL":
            emit(b"1" if cache.pop(parts[1], None) is not None else b"0")
        elif op == SIZE:
            emit(str(len(cache)).encode())

    if not out:
        return b""
    out.append(b"")
    return b"\n".join(out)


def main() -> None:
    sys.stdout.buffer.write(run(sys.stdin.buffer.read()))
    sys.stdout.buffer.flush()


if __name__ == "__main__":
    main()
