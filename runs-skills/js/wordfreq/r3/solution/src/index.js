#!/usr/bin/env node
import { WordCounter } from './wordfreq.js';

const TOP_N = 10;

const counter = new WordCounter();
for await (const chunk of process.stdin) counter.push(chunk);
counter.end();

const lines = counter.top(TOP_N).map(([word, count]) => `${count} ${word}\n`);
if (lines.length > 0) process.stdout.write(lines.join(''));
