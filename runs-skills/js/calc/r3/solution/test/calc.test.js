import { test } from 'node:test';
import { evaluateLine } from '../src/calc.js';

const cases = [
  ['1 + 2 * 3', '7'],
  ['-7 / 2', '-3'],
  ['(1 + 2', 'error'],
  ['9223372036854775807 + 1', 'error'],
  ['-7 % 3', '-1'],
  ['7 % -3', '1'],
  ['(-9223372036854775807 - 1) % -1', '0'],
  ['(-9223372036854775807 - 1) / -1', 'error'],
  ['-9223372036854775808', 'error'],
  ['-9223372036854775807 - 1', '-9223372036854775808'],
  ['--5', '5'],
  ['-(2 + 3)', '-5'],
  ['2 * -3', '-6'],
  ['-2 * 3 - -4', '-2'],
  ['10 - 4 - 3', '3'],
  ['()', 'error'],
  ['1 2', 'error'],
  ['+1', 'error'],
  ['1 +', 'error'],
  ['1)', 'error'],
  ['1 / 0', 'error'],
  ['5 % 0', 'error'],
  ['\t 42 ', '42'],
  ['1\r', 'error'],
  ['   ', null],
  ['', null],
  ['('.repeat(100000) + '1' + ')'.repeat(100000), '1'],
  ['-'.repeat(100001) + '1', '-1'],
];

for (const [input, want] of cases) {
  test(JSON.stringify(input.length > 40 ? input.slice(0, 40) + '…' : input), (t) => {
    t.assert.strictEqual(evaluateLine(input), want);
  });
}
