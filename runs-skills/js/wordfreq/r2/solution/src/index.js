#!/usr/bin/env node
import { WordCounter } from './word-counter.js';

const TOP_N = 10;

const counter = new WordCounter();
for await (const chunk of process.stdin) counter.add(chunk);
counter.finish();

const lines = counter.top(TOP_N).map(({ count, word }) => `${count} ${word}\n`);
process.stdout.write(lines.join(''));
