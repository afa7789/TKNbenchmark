/**
 * LRU cache simulator: reads a capacity and a stream of commands from stdin,
 * writes command results to stdout (see SPEC.md).
 */
import { LruCache } from './lru.ts';

const OUTPUT_FLUSH_THRESHOLD = 1 << 16;

class Simulator {
  #cache: LruCache<string, string> | undefined;
  #out: string[] = [];

  /** Handles one input line (without its terminator). */
  line(raw: string): void {
    const line = raw.endsWith('\r') ? raw.slice(0, -1) : raw;
    if (this.#cache === undefined) {
      this.#cache = new LruCache(Number.parseInt(line.trim(), 10));
      return;
    }
    if (line.length > 0) this.#execute(this.#cache, line);
  }

  #execute(cache: LruCache<string, string>, line: string): void {
    const sp1 = line.indexOf(' ');
    const cmd = sp1 < 0 ? line : line.slice(0, sp1);
    switch (cmd) {
      case 'SET': {
        const sp2 = line.indexOf(' ', sp1 + 1);
        if (sp1 < 0 || sp2 < 0) return;
        cache.set(line.slice(sp1 + 1, sp2), line.slice(sp2 + 1));
        return;
      }
      case 'GET':
        if (sp1 < 0) return;
        this.#emit(cache.get(line.slice(sp1 + 1)) ?? 'NULL');
        return;
      case 'DEL':
        if (sp1 < 0) return;
        this.#emit(cache.delete(line.slice(sp1 + 1)) ? '1' : '0');
        return;
      case 'SIZE':
        this.#emit(String(cache.size));
        return;
      default:
        return;
    }
  }

  #emit(s: string): void {
    this.#out.push(s);
    if (this.#out.length >= OUTPUT_FLUSH_THRESHOLD) this.flush();
  }

  flush(): void {
    if (this.#out.length === 0) return;
    process.stdout.write(this.#out.join('\n') + '\n');
    this.#out = [];
  }
}

async function main(): Promise<void> {
  const sim = new Simulator();
  let pending = '';
  process.stdin.setEncoding('latin1');
  for await (const chunk of process.stdin as AsyncIterable<string>) {
    const text = pending + chunk;
    let start = 0;
    let nl: number;
    while ((nl = text.indexOf('\n', start)) >= 0) {
      sim.line(text.slice(start, nl));
      start = nl + 1;
    }
    pending = text.slice(start);
  }
  if (pending.length > 0) sim.line(pending);
  sim.flush();
}

await main();
