/** Prints the ten most frequent ASCII words read from standard input. */
import type { Readable } from 'node:stream';
import { WordCounter } from './word-counter.ts';

const TOP_N = 10;
const LOWER_A = 0x61;
const LOWER_Z = 0x7a;
const CASE_BIT = 0x20;

/** Tokenizes the stream into maximal runs of ASCII letters, folded to lowercase. */
export async function count(input: Readable): Promise<WordCounter> {
  const counter = new WordCounter();
  let word = new Uint8Array(64);
  let wordLen = 0;

  for await (const chunk of input as AsyncIterable<Buffer>) {
    for (let i = 0, n = chunk.length; i < n; i++) {
      const lower = chunk[i] | CASE_BIT;
      if (lower >= LOWER_A && lower <= LOWER_Z) {
        if (wordLen === word.length) {
          const grown = new Uint8Array(word.length * 2);
          grown.set(word);
          word = grown;
        }
        word[wordLen++] = lower;
      } else if (wordLen > 0) {
        counter.add(word, wordLen);
        wordLen = 0;
      }
    }
  }
  if (wordLen > 0) counter.add(word, wordLen);
  return counter;
}

async function main(): Promise<void> {
  const counter = await count(process.stdin);
  const output = counter
    .top(TOP_N)
    .map(({ count, word }) => `${count} ${word}\n`)
    .join('');
  if (output.length > 0) process.stdout.write(output);
}

await main();
