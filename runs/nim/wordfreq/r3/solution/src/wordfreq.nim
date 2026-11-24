## wordfreq: print the 10 most frequent ASCII words read from standard input.

import std/[algorithm, tables]

const TopN = 10

type WordCount = tuple[word: string, count: int]

func toLowerAscii(c: char): char {.inline.} =
  if c in {'A'..'Z'}: char(ord(c) + 32) else: c

proc countWords(data: string): CountTable[string] =
  ## Counts maximal runs of ASCII letters, folded to lowercase.
  result = initCountTable[string]()
  var word = newStringOfCap(64)
  for c in data:
    if c in {'a'..'z', 'A'..'Z'}:
      word.add toLowerAscii(c)
    elif word.len > 0:
      result.inc word
      word.setLen 0
  if word.len > 0:
    result.inc word

func byFrequency(a, b: WordCount): int =
  ## Count descending, then word ascending (byte order).
  result = cmp(b.count, a.count)
  if result == 0:
    result = cmp(a.word, b.word)

proc topWords(counts: CountTable[string]; n: int): seq[WordCount] =
  result = newSeqOfCap[WordCount](counts.len)
  for word, count in counts:
    result.add (word, count)
  result.sort(byFrequency)
  if result.len > n:
    result.setLen n

proc main() =
  let counts = countWords(stdin.readAll())
  var output = ""
  for (word, count) in topWords(counts, TopN):
    output.add $count
    output.add ' '
    output.add word
    output.add '\n'
  stdout.write output
  stdout.flushFile()

when isMainModule:
  main()
