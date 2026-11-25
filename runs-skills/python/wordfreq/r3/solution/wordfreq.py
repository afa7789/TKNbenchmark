"""Print the 10 most frequent ASCII words read from standard input."""

import heapq
import string
import sys
from collections import Counter

TOP_N = 10

# Map uppercase ASCII letters to lowercase and every non-letter byte to a space,
# so a single translate + split yields the case-folded words.
_LETTERS = frozenset(string.ascii_letters.encode())
_FOLD_TABLE = bytes(
    (b | 0x20) if b in _LETTERS else 0x20 for b in range(256)
)


def top_words(data: bytes, n: int = TOP_N) -> list[tuple[bytes, int]]:
    """Return up to ``n`` (word, count) pairs: count descending, then word ascending."""
    counts = Counter(data.translate(_FOLD_TABLE).split())
    return heapq.nsmallest(n, counts.items(), key=lambda item: (-item[1], item[0]))


def main() -> int:
    data = sys.stdin.buffer.read()
    out = b"".join(b"%d %s\n" % (count, word) for word, count in top_words(data))
    sys.stdout.buffer.write(out)
    sys.stdout.buffer.flush()
    return 0


if __name__ == "__main__":
    sys.exit(main())
