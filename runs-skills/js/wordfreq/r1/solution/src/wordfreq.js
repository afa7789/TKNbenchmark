// wordfreq: print the 10 most frequent ASCII words read from standard input.

const TOP_N = 10;

const isUpper = (b) => b >= 0x41 && b <= 0x5a;
const isLower = (b) => b >= 0x61 && b <= 0x7a;

/**
 * Count case-folded words (maximal runs of ASCII letters) in a byte buffer.
 * The buffer is lowercased in place.
 * @param {Buffer} buf
 * @returns {Map<string, number>}
 */
export function countWords(buf) {
  for (let i = 0; i < buf.length; i++) {
    if (isUpper(buf[i])) buf[i] |= 0x20;
  }
  // latin1 maps each byte to one UTF-16 code unit, so offsets line up.
  const text = buf.toString('latin1');
  const counts = new Map();
  const n = text.length;
  let i = 0;
  while (i < n) {
    if (!isLower(text.charCodeAt(i))) {
      i++;
      continue;
    }
    const start = i;
    do i++;
    while (i < n && isLower(text.charCodeAt(i)));
    const word = text.slice(start, i);
    counts.set(word, (counts.get(word) ?? 0) + 1);
  }
  return counts;
}

const byCountThenWord = ([wa, ca], [wb, cb]) => cb - ca || (wa < wb ? -1 : wa > wb ? 1 : 0);

/**
 * @param {Map<string, number>} counts
 * @param {number} [n]
 * @returns {Array<[string, number]>}
 */
export function topWords(counts, n = TOP_N) {
  const top = [];
  for (const entry of counts) {
    if (top.length === n && byCountThenWord(entry, top[n - 1]) >= 0) continue;
    let j = top.length < n ? top.length : n - 1;
    while (j > 0 && byCountThenWord(entry, top[j - 1]) < 0) {
      top[j] = top[j - 1];
      j--;
    }
    top[j] = entry;
  }
  return top;
}

async function readAll(stream) {
  const chunks = [];
  for await (const chunk of stream) chunks.push(chunk);
  return Buffer.concat(chunks);
}

async function main() {
  const counts = countWords(await readAll(process.stdin));
  const lines = topWords(counts).map(([word, count]) => `${count} ${word}\n`);
  if (lines.length > 0) process.stdout.write(lines.join(''));
}

if (import.meta.main) await main();
