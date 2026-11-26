/** Simulate an LRU cache driven by commands read from standard input. */
import { readFileSync, writeSync } from "node:fs";
import { LruCache } from "./lru-cache.ts";

const NULL = "NULL";

/** ASCII whitespace as understood by Python's bytes.split(): space, \t, \n, \v, \f, \r. */
function isSpace(code: number): boolean {
  return code === 0x20 || (code >= 0x09 && code <= 0x0d);
}

/** Split a line into whitespace-separated tokens. */
function tokenize(line: string): string[] {
  const tokens: string[] = [];
  const length = line.length;
  let i = 0;
  while (i < length) {
    while (i < length && isSpace(line.charCodeAt(i))) i++;
    if (i === length) break;
    const start = i;
    while (i < length && !isSpace(line.charCodeAt(i))) i++;
    tokens.push(line.slice(start, i));
  }
  return tokens;
}

/** Parse the capacity line; returns undefined if it is not an integer. */
function parseCapacity(line: string | undefined): number | undefined {
  const text = line?.replace(/^[\t-\r ]+|[\t-\r ]+$/g, "");
  if (!text || !/^[+-]?\d+(?:_\d+)*$/.test(text)) return undefined;
  return Number(text.replaceAll("_", ""));
}

export function run(input: string): string {
  const lines = input.split("\n");
  const capacity = parseCapacity(lines[0]);
  if (capacity === undefined) return "";

  const cache = new LruCache(capacity);
  const out: string[] = [];

  for (let i = 1; i < lines.length; i++) {
    const [command, key, value] = tokenize(lines[i]);
    switch (command) {
      case "GET":
        if (key !== undefined) out.push(cache.get(key) ?? NULL);
        break;
      case "SET":
        if (key !== undefined && value !== undefined) cache.set(key, value);
        break;
      case "DEL":
        if (key !== undefined) out.push(cache.delete(key) ? "1" : "0");
        break;
      case "SIZE":
        out.push(String(cache.size));
        break;
    }
  }

  return out.length === 0 ? "" : out.join("\n") + "\n";
}

function writeAll(fd: number, data: Buffer): void {
  let offset = 0;
  while (offset < data.length) {
    try {
      offset += writeSync(fd, data, offset);
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code !== "EAGAIN") throw error;
    }
  }
}

function main(): void {
  const input = readFileSync(0, "latin1");
  writeAll(1, Buffer.from(run(input), "latin1"));
}

main();
