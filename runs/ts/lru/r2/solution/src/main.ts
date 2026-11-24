import { readFileSync, writeSync } from "node:fs";
import { LruCache } from "./lru.ts";

function readStdin(): string {
  try {
    return readFileSync(0, "latin1");
  } catch (err) {
    // An empty or closed stdin is treated as no input.
    if ((err as NodeJS.ErrnoException).code === "EAGAIN" || (err as NodeJS.ErrnoException).code === "EOF") return "";
    throw err;
  }
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

function run(input: string): string {
  const lines = input.split("\n");
  const capacity = Number.parseInt(lines[0] ?? "", 10);
  if (!Number.isInteger(capacity) || capacity < 1) return "";

  const cache = new LruCache(capacity);
  const out: string[] = [];

  for (let i = 1; i < lines.length; i++) {
    let line = lines[i];
    if (line.endsWith("\r")) line = line.slice(0, -1);
    if (line.length === 0) continue;

    const sp1 = line.indexOf(" ");
    const cmd = sp1 === -1 ? line : line.slice(0, sp1);
    switch (cmd) {
      case "SET": {
        const sp2 = line.indexOf(" ", sp1 + 1);
        if (sp2 === -1) break;
        cache.set(line.slice(sp1 + 1, sp2), line.slice(sp2 + 1));
        break;
      }
      case "GET":
        if (sp1 !== -1) out.push(cache.get(line.slice(sp1 + 1)) ?? "NULL");
        break;
      case "DEL":
        if (sp1 !== -1) out.push(cache.delete(line.slice(sp1 + 1)) ? "1" : "0");
        break;
      case "SIZE":
        out.push(String(cache.size));
        break;
      default:
        // Unknown commands are ignored.
        break;
    }
  }

  return out.length === 0 ? "" : out.join("\n") + "\n";
}

writeAll(run(readStdin()));
