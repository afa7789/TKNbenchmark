## wordfreq: print the 10 most frequent ASCII words read from standard input.

import std/[algorithm, tables]

const TopN = 10

type WordCount = tuple[word: string, count: int]

func toLowerAscii(c: char): char {.inline.} =
  if c in {'A'..'Z'}: char(ord(c) + 32) else: c

proc countWords(data: string): Table[string, int] =
  ## Counts maximal runs of ASCII letters, folded to lowercase.
  result = initTable[string, int]()
  var word = newStringOfCap(64)
  for c in data:
    if c in {'a'..'z', 'A'..'Z'}:
      word.add toLowerAscii(c)
    elif word.len > 0:
      result.mgetOrPut(word, 0).inc
      word.setLen 0
  if word.len > 0:
    result.mgetOrPut(word, 0).inc

func byFrequency(a, b: WordCount): int =
  ## Count descending, then word ascending (byte order).
  result = cmp(b.count, a.count)
  if result == 0:
    result = cmp(a.word, b.word)

proc topWords(counts: Table[string, int]; n: int): seq[WordCount] =
  ## Selects the `n` best entries without sorting the whole table.
  result = newSeqOfCap[WordCount](n + 1)
  for word, count in counts:
    let entry: WordCount = (word, count)
    if result.len == n and byFrequency(entry, result[^1]) >= 0:
      continue
    result.insert(entry, result.upperBound(entry, byFrequency))
    if result.len > n:
      result.setLen n

proc main() =
  let data = stdin.readAll()
  var output = ""
  for (word, count) in topWords(countWords(data), TopN):
    output.add $count
    output.add ' '
    output.add word
    output.add '\n'
  stdout.write output
  stdout.flushFile()

when isMainModule:
  main()
