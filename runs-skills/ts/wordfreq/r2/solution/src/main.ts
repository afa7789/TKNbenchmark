import { topWords } from './wordfreq.ts';

const TOP_N = 10;

async function readStdin(): Promise<Buffer> {
  const chunks: Buffer[] = [];
  for await (const chunk of process.stdin) chunks.push(chunk as Buffer);
  return Buffer.concat(chunks);
}

const input = await readStdin();
const lines = topWords(input, TOP_N).map(({ count, word }) => `${count} ${word}\n`);
process.stdout.write(lines.join(''));
