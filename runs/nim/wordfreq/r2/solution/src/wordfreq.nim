## wordfreq: print the 10 most frequent ASCII words read from standard input.

import std/[algorithm, tables]

const
  TopN = 10
  ChunkSize = 1 shl 16

type WordCount = tuple[word: string, count: int]

func toLowerAscii(c: char): char {.inline.} =
  if c in {'A'..'Z'}: char(ord(c) + 32) else: c

proc countWords(f: File): CountTable[string] =
  ## Streams `f` in chunks, counting lowercase runs of ASCII letters.
  ## A word split across chunk boundaries is carried over in `word`.
  result = initCountTable[string]()
  var
    buf = newString(ChunkSize)
    word = newStringOfCap(64)
  while true:
    let n = f.readBuffer(buf[0].addr, ChunkSize)
    if n <= 0: break
    for i in 0 ..< n:
      let c = buf[i]
      if c in {'A'..'Z', 'a'..'z'}:
        word.add c.toLowerAscii
      elif word.len > 0:
        result.inc word
        word.setLen 0
  if word.len > 0:
    result.inc word

func byRank(a, b: WordCount): int =
  result = cmp(b.count, a.count)
  if result == 0:
    result = cmp(a.word, b.word)

proc topWords(counts: CountTable[string], n: int): seq[WordCount] =
  result = newSeqOfCap[WordCount](counts.len)
  for word, count in counts.pairs:
    result.add (word, count)
  result.sort(byRank)
  if result.len > n:
    result.setLen n

proc main() =
  var output = ""
  for (word, count) in topWords(countWords(stdin), TopN):
    output.add $count
    output.add ' '
    output.add word
    output.add '\n'
  stdout.write output
  stdout.flushFile

when isMainModule:
  main()
