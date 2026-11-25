"""Simulate an LRU cache driven by commands on standard input."""

import sys
from collections import OrderedDict
from collections.abc import Iterable


def run(lines: Iterable[bytes], capacity: int) -> list[bytes]:
    """Execute cache commands and return the output lines."""
    cache: OrderedDict[bytes, bytes] = OrderedDict()
    out: list[bytes] = []
    emit = out.append
    move_to_end = cache.move_to_end
    pop = cache.pop
    popitem = cache.popitem

    for line in lines:
        parts = line.split()
        if not parts:
            continue
        match parts:
            case [b"SET", key, value]:
                if key in cache:
                    move_to_end(key)
                cache[key] = value
                if len(cache) > capacity:
                    popitem(last=False)
            case [b"GET", key]:
                value = cache.get(key)
                if value is None:
                    emit(b"NULL")
                else:
                    move_to_end(key)
                    emit(value)
            case [b"DEL", key]:
                emit(b"0" if pop(key, None) is None else b"1")
            case [b"SIZE"]:
                emit(str(len(cache)).encode())
            case _:
                pass  # Malformed commands are ignored.
    return out


def main() -> int:
    data = sys.stdin.buffer.read().splitlines()
    if not data:
        return 0
    capacity = int(data[0])
    out = run(data[1:], capacity)
    if out:
        sys.stdout.buffer.write(b"\n".join(out) + b"\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
