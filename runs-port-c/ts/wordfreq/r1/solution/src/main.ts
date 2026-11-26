/**
 * wordfreq: read stdin, print the 10 most frequent ASCII-letter words
 * (case-folded), ordered by count descending, then word ascending.
 */
import { WordCounter } from "./wordfreq.ts";

const TOP_N = 10;

async function main(): Promise<void> {
  const counter = new WordCounter();
  for await (const chunk of process.stdin) {
    counter.push(chunk as Buffer);
  }
  counter.end();

  const output = counter
    .top(TOP_N)
    .map(({ word, count }) => `${count} ${word}\n`)
    .join("");
  if (output !== "") process.stdout.write(output);
}

await main();
