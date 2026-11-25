## wordfreq: print the 10 most frequent ASCII words read from standard input.

import std/[algorithm, tables]

const TopN = 10

type WordCount = tuple[word: string, count: int]

proc countWords(data: string): Table[string, int] =
  ## Counts maximal runs of ASCII letters, folded to lowercase.
  result = initTable[string, int]()
  var word = newStringOfCap(64)
  template flush() =
    if word.len > 0:
      result.withValue(word, n):
        inc n[]
      do:
        result[word] = 1
      word.setLen(0)
  for c in data:
    case c
    of 'a'..'z': word.add c
    of 'A'..'Z': word.add chr(ord(c) + (ord('a') - ord('A')))
    else: flush()
  flush()

proc byFrequency(a, b: WordCount): int =
  ## Count descending, then word ascending (byte order).
  result = cmp(b.count, a.count)
  if result == 0: result = cmp(a.word, b.word)

proc topWords(counts: Table[string, int]; n: int): seq[WordCount] =
  result = newSeqOfCap[WordCount](counts.len)
  for word, count in counts: result.add (word, count)
  result.sort(byFrequency)
  if result.len > n: result.setLen(n)

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
