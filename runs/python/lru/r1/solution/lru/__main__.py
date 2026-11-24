"""Simulate an LRU cache driven by commands on standard input.

Input: the capacity on the first line, then one command per line:
``SET <key> <value>``, ``GET <key>``, ``DEL <key>`` or ``SIZE``.
"""

from __future__ import annotations

import sys
from collections import OrderedDict
from collections.abc import Iterable, Iterator

NULL = b"NULL"


def run(capacity: int, lines: Iterable[bytes]) -> Iterator[bytes]:
    """Execute cache commands, yielding one output line per producing command."""
    cache: OrderedDict[bytes, bytes] = OrderedDict()
    move_to_end = cache.move_to_end
    popitem = cache.popitem
    get = cache.get
    pop = cache.pop

    for line in lines:
        parts = line.split()
        if not parts:
            continue
        cmd = parts[0]
        if cmd == b"SET":
            key = parts[1]
            if key in cache:
                move_to_end(key)
                cache[key] = parts[2]
            else:
                cache[key] = parts[2]
                if len(cache) > capacity:
                    popitem(last=False)
        elif cmd == b"GET":
            key = parts[1]
            value = get(key)
            if value is None:
                yield NULL
            else:
                move_to_end(key)
                yield value
        elif cmd == b"DEL":
            yield b"1" if pop(parts[1], None) is not None else b"0"
        elif cmd == b"SIZE":
            yield str(len(cache)).encode()


def main() -> int:
    data = sys.stdin.buffer.read()
    lines = data.split(b"\n")
    if not lines or not lines[0].strip():
        return 0
    capacity = int(lines[0])
    out = list(run(capacity, lines[1:]))
    if out:
        sys.stdout.buffer.write(b"\n".join(out) + b"\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
