import { WordCounter, formatCounts } from './wordfreq.ts';

const TOP_N = 10;

const counter = new WordCounter();
for await (const chunk of process.stdin) {
  counter.write(chunk as Buffer);
}
counter.end();

const output = formatCounts(counter.top(TOP_N));
if (output.length > 0) process.stdout.write(output);
