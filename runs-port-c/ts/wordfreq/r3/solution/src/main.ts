import { WordCounter } from "./wordfreq.ts";

const TOP_N = 10;

async function main(): Promise<void> {
  const counter = new WordCounter();
  for await (const chunk of process.stdin) {
    counter.feed(chunk as Buffer);
  }
  counter.finish();

  const lines = counter.top(TOP_N).map(({ word, count }) => `${count} ${word}\n`);
  process.stdout.write(lines.join(""));
}

main().catch((err: unknown) => {
  process.stderr.write(`wordfreq: ${err instanceof Error ? err.message : String(err)}\n`);
  process.exitCode = 1;
});
