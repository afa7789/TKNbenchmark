"""Simulate an LRU cache driven by commands read from standard input.

Input: the first line is the capacity; each later line is one of
``SET <key> <value>``, ``GET <key>``, ``DEL <key>`` or ``SIZE``.
"""

import sys
from collections import OrderedDict
from collections.abc import Iterable

NULL = b"NULL"


def run(capacity: int, commands: Iterable[bytes]) -> list[bytes]:
    """Execute ``commands`` against an LRU cache of ``capacity`` keys.

    Returns the output lines (without terminators). Every command is O(1)
    expected time thanks to ``OrderedDict``'s linked-list ordering.
    """
    cache: OrderedDict[bytes, bytes] = OrderedDict()
    out: list[bytes] = []
    emit = out.append
    get = cache.get
    pop = cache.pop
    touch = cache.move_to_end
    evict = cache.popitem

    for line in commands:
        parts = line.split()
        if not parts:
            continue
        match parts:
            case [b"SET", key, value]:
                if key in cache:
                    touch(key)
                cache[key] = value
                if len(cache) > capacity:
                    evict(last=False)
            case [b"GET", key]:
                value = get(key)
                if value is None:
                    emit(NULL)
                else:
                    touch(key)
                    emit(value)
            case [b"DEL", key]:
                emit(b"0" if pop(key, None) is None else b"1")
            case [b"SIZE"]:
                emit(str(len(cache)).encode())
            case _:
                raise ValueError(f"malformed command: {line!r}")
    return out


def main() -> int:
    lines = sys.stdin.buffer.read().split(b"\n")
    if not lines or not lines[0].strip():
        return 0
    capacity = int(lines[0])
    out = run(capacity, lines[1:])
    if out:
        sys.stdout.buffer.write(b"\n".join(out) + b"\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
