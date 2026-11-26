# suite

One command-line program `./app` with three subcommands. The first argument selects one; each reads
standard input and writes standard output exactly as its section below specifies, and exits with status 0.

- `./app wordfreq`: word frequencies.
- `./app lru`: an LRU cache simulator.
- `./app calc`: a 64-bit integer expression evaluator.

The three are independent: no state is shared between them, and each must meet its own size and speed
limits (inputs up to 50 MB for `wordfreq`, a million commands for `lru`).

## wordfreq

`./app wordfreq`.

Read all of standard input and print the 10 most frequent words.

- A **word** is a maximal run of ASCII letters `A–Z` / `a–z`. Every other byte (digits, `_`, `'`,
  punctuation, whitespace, bytes ≥ 0x80) is a separator.
- Words are case-insensitive: fold them to lowercase.
- Output one line per word: `<count> <word>`, ordered by count descending, ties broken by word
  ascending (byte order). Print at most 10 lines; fewer if there are fewer distinct words.
  Input with no words prints nothing.
- Input can be up to 50 MB and may contain arbitrary bytes, including invalid UTF-8.
- Exit with status 0.

Example — input `The cat and the hat.` prints:

```
2 the
1 and
1 cat
1 hat
```

## lru

`./app lru` that simulates an LRU (least-recently-used) cache.

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

## calc

`./app calc`: a 64-bit signed integer expression evaluator.

Each line of standard input is one expression. For each line print its value, or `error`.
A line that is empty or holds only spaces/tabs prints nothing. Lines end with `\n`.

Grammar (spaces and tabs may appear between any two tokens):

```
expr    := term    (('+' | '-') term)*
term    := unary   (('*' | '/' | '%') unary)*
unary   := '-' unary | primary
primary := NUMBER | '(' expr ')'
NUMBER  := [0-9]+
```

Operators are left-associative. There is no unary `+`.

Semantics — all values are signed 64-bit integers (−9223372036854775808 … 9223372036854775807):

- `/` truncates toward zero. `%` is the remainder of that division, so its sign follows the dividend
  (`-7 % 3` is `-1`, `7 % -3` is `1`).
- The line prints `error` when **any** of these happens:
  - syntax error (any character outside the grammar, unbalanced parentheses, missing operand…);
  - division or remainder by zero;
  - overflow: a literal greater than 9223372036854775807, or any `+ - * /` or unary `-` whose exact
    result is outside the 64-bit range. (`(-9223372036854775807 - 1) % -1` is `0`, not an error.)
- Exit with status 0.

Example — input:

```
1 + 2 * 3
-7 / 2
(1 + 2
9223372036854775807 + 1
```

prints:

```
7
-3
error
error
```
