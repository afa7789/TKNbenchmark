# wordfreq

Command-line program `./app` (no arguments).

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
