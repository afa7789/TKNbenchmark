import { test } from 'node:test';
import assert from 'node:assert/strict';
import { evaluateLines } from '../src/calc.js';

const run = (s) => evaluateLines(s).join('\n');

test('spec example', () => {
  assert.equal(run('1 + 2 * 3\n-7 / 2\n(1 + 2\n9223372036854775807 + 1\n'), '7\n-3\nerror\nerror');
});

test('64-bit edges', () => {
  assert.equal(run('(-9223372036854775807 - 1) % -1'), '0');
  assert.equal(run('(-9223372036854775807 - 1) / -1'), 'error');
  assert.equal(run('-(-9223372036854775807 - 1)'), 'error');
  assert.equal(run('-9223372036854775807 - 1'), '-9223372036854775808');
  assert.equal(run('9223372036854775808'), 'error');
  assert.equal(run('-9223372036854775808'), 'error');
  assert.equal(run('3037000500 * 3037000500'), 'error');
});

test('syntax errors', () => {
  for (const s of ['1 +', '()', '1 2', '+1', ')', '1)', '(1', '1 + * 2', '1\r', '- ', '1 -']) {
    assert.equal(run(s), 'error', s);
  }
});

test('deep nesting', () => {
  const d = 200000;
  assert.equal(run('('.repeat(d) + '1' + ')'.repeat(d)), '1');
  assert.equal(run('-'.repeat(d) + '1'), '1');
});
