import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { evaluate, isBlankLine } from '../src/calc.ts';

describe('evaluate', () => {
  const ok: Array<[string, bigint]> = [
    ['1 + 2 * 3', 7n],
    ['-7 / 2', -3n],
    ['-7 % 3', -1n],
    ['7 % -3', 1n],
    ['10 - 4 - 3', 3n],
    ['--5', 5n],
    ['-(2 + 3)', -5n],
    ['2 * -3', -6n],
    ['(-9223372036854775807 - 1) % -1', 0n],
    ['-9223372036854775807 - 1', -(1n << 63n)],
    ['((((1))))', 1n],
    ['\t1\t+ 1 ', 2n],
  ];
  for (const [src, want] of ok) it(`${src} = ${want}`, () => assert.equal(evaluate(src), want));

  const bad = [
    '(1 + 2', '1 +', 'abc', '()', '1 2', '+1', '1 / 0', '5 % 0', ')', '1)', '(1))',
    '9223372036854775807 + 1', '9223372036854775808', '-9223372036854775808',
    '(-9223372036854775807 - 1) / -1', '-(-9223372036854775807 - 1)', '3037000500 * 3037000500', '1\r',
  ];
  for (const src of bad) it(`${JSON.stringify(src)} is an error`, () => assert.equal(evaluate(src), undefined));

  it('handles deep nesting without recursion', () => {
    const d = 200_000;
    assert.equal(evaluate('('.repeat(d) + '1' + ')'.repeat(d)), 1n);
    assert.equal(evaluate('-'.repeat(d) + '1'), 1n);
  });
});

describe('isBlankLine', () => {
  it('detects blanks', () => {
    assert.ok(isBlankLine(''));
    assert.ok(isBlankLine(' \t '));
    assert.ok(!isBlankLine(' 1 '));
  });
});
