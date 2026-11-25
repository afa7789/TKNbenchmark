import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { evaluateLine } from '../src/calc.ts';

const cases: [string, string | undefined][] = [
  ['1 + 2 * 3', '7'],
  ['-7 / 2', '-3'],
  ['(1 + 2', 'error'],
  ['9223372036854775807 + 1', 'error'],
  ['-7 % 3', '-1'],
  ['7 % -3', '1'],
  ['(-9223372036854775807 - 1) % -1', '0'],
  ['(-9223372036854775807 - 1) / -1', 'error'],
  ['-(-9223372036854775807 - 1)', 'error'],
  ['-9223372036854775808', 'error'],
  ['-9223372036854775807 - 1', '-9223372036854775808'],
  ['--5', '5'],
  ['2 * -3', '-6'],
  ['-2 * 3 - -4', '-2'],
  ['10 - 4 - 3', '3'],
  ['100 / 10 / 5', '2'],
  ['1 +', 'error'],
  ['()', 'error'],
  ['1 2', 'error'],
  ['+1', 'error'],
  [')1(', 'error'],
  ['1)', 'error'],
  ['1 - (2)', '-1'],
  ['  \t ', undefined],
  ['', undefined],
  ['1\r', 'error'],
  ['0000000000000000000000000000001', '1'],
];

describe('evaluateLine', () => {
  for (const [input, want] of cases) {
    it(JSON.stringify(input), () => assert.equal(evaluateLine(input), want));
  }
  it('handles deep nesting', () => {
    const n = 200_000;
    assert.equal(evaluateLine('('.repeat(n) + '1' + ')'.repeat(n)), '1');
    assert.equal(evaluateLine('-'.repeat(n) + '1'), '1');
  });
});
