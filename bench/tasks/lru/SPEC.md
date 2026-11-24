# lru

Command-line program `./app` (no arguments) that simulates an LRU (least-recently-used) cache.

Standard input:

- Line 1: the capacity `C`, an integer with 1 ≤ C ≤ 1,000,000.
- Each later line is one command. Keys and values are 1–64 printable ASCII characters with no
  spaces. Tokens are separated by a single space. Lines end with `\n`; the last line may lack it.

Commands:

| Command | Effect | Output |
|---|---|---|
| `SET <key> <value>` | Insert or overwrite. The key becomes the most recently used. If the cache now holds more than `C` keys, evict the least recently used one. | nothing |
| `GET <key>` | Look up. A hit makes the key the most recently used. | the value, or `NULL` |
| `DEL <key>` | Remove the key. | `1` if it was present, else `0` |
| `SIZE` | — | the number of keys held |

Each output goes on its own line. Up to 1,000,000 commands: every command must run in O(1)
expected time. Exit with status 0.

Example — input:

```
2
SET a 1
SET b 2
GET a
SET c 3
GET b
SIZE
```

prints:

```
1
NULL
2
```
