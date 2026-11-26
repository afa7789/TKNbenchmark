/**
 * Simulate an LRU cache driven by commands on standard input.
 *
 * Input: the capacity on the first line, then one command per line:
 * `SET <key> <value>`, `GET <key>`, `DEL <key>` or `SIZE`.
 */
import { readFileSync, writeSync } from "node:fs";
import { LruCache } from "./lru-cache.ts";

const NULL = "NULL";
const WHITESPACE = /[ \t\n\r\v\f]+/;

/** Executes cache commands, returning one output line per producing command. */
export function run(capacity: number, lines: Iterable<string>): string[] {
  const cache = new LruCache<string>(capacity);
  const out: string[] = [];

  for (const line of lines) {
    const parts = line.trim().split(WHITESPACE);
    const [cmd, key, value] = parts;
    switch (cmd) {
      case "SET":
        if (key !== undefined && value !== undefined) cache.set(key, value);
        break;
      case "GET":
        if (key !== undefined) out.push(cache.get(key) ?? NULL);
        break;
      case "DEL":
        if (key !== undefined) out.push(cache.delete(key) ? "1" : "0");
        break;
      case "SIZE":
        out.push(String(cache.size));
        break;
      default:
        // Blank lines and unknown commands are ignored.
        break;
    }
  }
  return out;
}

function writeAll(text: string): void {
  const buf = Buffer.from(text, "latin1");
  let offset = 0;
  while (offset < buf.length) {
    try {
      offset += writeSync(1, buf, offset);
    } catch (err) {
      if ((err as NodeJS.ErrnoException).code !== "EAGAIN") throw err;
    }
  }
}

function main(): number {
  const lines = readFileSync(0, "latin1").split("\n");
  const header = lines[0]?.trim() ?? "";
  if (header === "") return 0;

  const capacity = Number(header);
  if (!Number.isInteger(capacity) || capacity < 1) {
    process.stderr.write(`invalid capacity: ${header}\n`);
    return 1;
  }

  const out = run(capacity, lines.slice(1));
  if (out.length > 0) writeAll(out.join("\n") + "\n");
  return 0;
}

process.exitCode = main();
