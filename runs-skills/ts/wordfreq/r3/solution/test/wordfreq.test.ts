import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { WordCounter, formatCounts } from '../src/wordfreq.ts';

function run(input: string | Uint8Array, chunkSize = Infinity): string {
  const bytes = typeof input === 'string' ? Buffer.from(input, 'latin1') : input;
  const counter = new WordCounter();
  const step = Math.min(chunkSize, Math.max(bytes.length, 1));
  for (let i = 0; i < bytes.length; i += step) counter.write(bytes.subarray(i, i + step));
  counter.end();
  return formatCounts(counter.top(10));
}

describe('WordCounter', () => {
  it('counts the spec example', () => {
    assert.equal(run('The cat and the hat.'), '2 the\n1 and\n1 cat\n1 hat\n');
  });

  it('prints nothing for input without words', () => {
    assert.equal(run(''), '');
    assert.equal(run('123 _ \' \xff\xc3('), '');
  });

  it('treats non-letters as separators', () => {
    assert.equal(run("don't stop_me 4now, now-NOW"), '3 now\n1 don\n1 me\n1 stop\n1 t\n');
    assert.equal(run('caf\xc3\xa9s'), '1 caf\n1 s\n');
  });

  it('limits to ten and breaks ties by byte order', () => {
    const words = 'zeta eta theta iota kappa lambda mu nu xi omicron pi rho alpha beta alpha';
    assert.equal(run(words), '2 alpha\n1 beta\n1 eta\n1 iota\n1 kappa\n1 lambda\n1 mu\n1 nu\n1 omicron\n1 pi\n');
    assert.equal(run('ab a abc a ab'), '2 a\n2 ab\n1 abc\n');
  });

  it('handles words spanning chunk boundaries', () => {
    const text = 'Hello, hello! HELLO? world.\nworldwide hello';
    for (const size of [1, 2, 3, 7]) assert.equal(run(text, size), run(text));
  });

  it('survives table and arena growth', () => {
    const parts: string[] = [];
    for (let i = 0; i < 50_000; i++) parts.push(i.toString(26).replace(/\d/g, (d) => 'qrstuvwxyz'[Number(d)]!));
    parts.push('aaa', 'aaa', 'aaa');
    assert.match(run(parts.join(' '), 4096), /^4 aaa\n/);
  });
});
