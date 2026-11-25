"""Print the 10 most frequent ASCII words read from standard input."""

import heapq
import string
import sys
from collections import Counter

TOP_N = 10

# Map ASCII letters to lowercase and every other byte to a space separator.
_LETTERS = string.ascii_letters.encode()
_TABLE = bytes(
    (b | 0x20) if b in _LETTERS else 0x20 for b in range(256)
)


def top_words(data: bytes, n: int = TOP_N) -> list[tuple[bytes, int]]:
    """Return up to n (word, count) pairs by count descending, then word ascending."""
    counts = Counter(data.translate(_TABLE).split())
    return heapq.nsmallest(n, counts.items(), key=lambda item: (-item[1], item[0]))


def main() -> int:
    data = sys.stdin.buffer.read()
    out = sys.stdout.buffer
    out.write(b"".join(b"%d %s\n" % (count, word) for word, count in top_words(data)))
    out.flush()
    return 0


if __name__ == "__main__":
    sys.exit(main())
