"""Print the 10 most frequent ASCII words read from standard input."""

from __future__ import annotations

import heapq
import string
import sys
from collections import Counter
from typing import BinaryIO, Iterator

TOP_N = 10
CHUNK_SIZE = 1 << 20

# Map ASCII letters to lowercase and every other byte to a space separator.
_LETTERS = (string.ascii_lowercase + string.ascii_uppercase).encode()
_FOLD_TABLE = bytes(
    ord(chr(b).lower()) if b in _LETTERS else ord(" ") for b in range(256)
)


def iter_words(stream: BinaryIO, chunk_size: int = CHUNK_SIZE) -> Iterator[list[bytes]]:
    """Yield batches of lowercase words, never splitting a word across chunks."""
    carry = b""
    while chunk := stream.read(chunk_size):
        text = carry + chunk.translate(_FOLD_TABLE)
        cut = text.rfind(b" ") + 1
        carry = text[cut:]
        yield text[:cut].split()
    if carry:
        yield [carry]


def top_words(counts: Counter[bytes], n: int = TOP_N) -> list[tuple[bytes, int]]:
    """Return the n most frequent words: count descending, then word ascending."""
    return heapq.nsmallest(n, counts.items(), key=lambda item: (-item[1], item[0]))


def main() -> int:
    counts: Counter[bytes] = Counter()
    for words in iter_words(sys.stdin.buffer):
        counts.update(words)
    out = b"".join(b"%d %s\n" % (count, word) for word, count in top_words(counts))
    sys.stdout.buffer.write(out)
    sys.stdout.buffer.flush()
    return 0


if __name__ == "__main__":
    sys.exit(main())
