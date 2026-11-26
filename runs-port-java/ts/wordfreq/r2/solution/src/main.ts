/** Prints the ten most frequent ASCII-letter words read from standard input. */
import type { Readable } from 'node:stream';
import { WordCounter } from './wordCounter.ts';

const TOP_N = 10;
const ASCII_CASE_BIT = 0x20;
const LOWER_A = 0x61;
const LOWER_Z = 0x7a;

/** Tokenizes the stream into lowercase words and counts them. */
export async function count(input: Readable): Promise<WordCounter> {
  const counter = new WordCounter();
  let word = new Uint8Array(64);
  let wordLength = 0;
  for await (const chunk of input as AsyncIterable<Uint8Array>) {
    for (let i = 0; i < chunk.length; i++) {
      const lower = chunk[i] | ASCII_CASE_BIT;
      if (lower >= LOWER_A && lower <= LOWER_Z) {
        if (wordLength === word.length) {
          const grown = new Uint8Array(word.length * 2);
          grown.set(word);
          word = grown;
        }
        word[wordLength++] = lower;
      } else if (wordLength > 0) {
        counter.add(word, wordLength);
        wordLength = 0;
      }
    }
  }
  if (wordLength > 0) {
    counter.add(word, wordLength);
  }
  return counter;
}

async function main(): Promise<void> {
  const counter = await count(process.stdin);
  const out = counter
    .top(TOP_N)
    .map(({ count, word }) => `${count} ${word}\n`)
    .join('');
  process.stdout.write(out, 'latin1');
}

await main();
