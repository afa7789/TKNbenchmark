/** Reads standard input and prints the ten most frequent ASCII words. */
import { WordScanner } from "./word-scanner.ts";

const TOP_N = 10;

async function main(): Promise<void> {
  const scanner = new WordScanner();
  for await (const chunk of process.stdin) {
    scanner.feed(chunk as Buffer);
  }
  const lines = scanner
    .finish()
    .top(TOP_N)
    .map(({ count, word }) => `${count} ${word}\n`)
    .join("");
  if (lines.length > 0) {
    process.stdout.write(lines);
  }
}

await main();
