/**
 * wordfreq: read stdin, print the 10 most frequent ASCII words.
 *
 * A word is a maximal run of ASCII letters, folded to lowercase. Output is
 * "<count> <word>" per line, ordered by count descending, then word ascending
 * (byte order), at most TOP_N lines.
 */

const TOP_N = 10;

                     
                        
                         
 

/** True if byte `c` is an ASCII letter (A–Z or a–z). */
function isAlpha(c        )          {
  return ((c | 0x20) - 0x61) >>> 0 < 26;
}

async function readStdin()                  {
  const chunks           = [];
  for await (const chunk of process.stdin) {
    chunks.push(chunk          );
  }
  return Buffer.concat(chunks);
}

/** Count lowercase-folded words in `data`. Folds letters in place. */
function countWords(data        )                      {
  const counts = new Map                ();
  const n = data.length;
  let i = 0;
  while (i < n) {
    while (i < n && !isAlpha(data[i])) i++;
    const start = i;
    while (i < n) {
      const c = data[i];
      if (!isAlpha(c)) break;
      data[i] = c | 0x20;
      i++;
    }
    if (i === start) break;
    const word = data.latin1Slice(start, i);
    counts.set(word, (counts.get(word) ?? 0) + 1);
  }
  return counts;
}

/** True if a ranks before b: higher count, then lexicographically smaller word. */
function ranksBefore(a           , b           )          {
  if (a.count !== b.count) return a.count > b.count;
  return a.word < b.word;
}

/** Select the top `max` entries, sorted best-first. */
function selectTop(counts                     , max        )              {
  const top              = [];
  for (const [word, count] of counts) {
    const entry            = { word, count };
    if (top.length === max && !ranksBefore(entry, top[max - 1])) continue;
    let pos = top.length < max ? top.length : max - 1;
    if (top.length < max) top.push(entry);
    while (pos > 0 && ranksBefore(entry, top[pos - 1])) {
      top[pos] = top[pos - 1];
      pos--;
    }
    top[pos] = entry;
  }
  return top;
}

async function main()                {
  const data = await readStdin();
  const top = selectTop(countWords(data), TOP_N);
  const out = top.map(({ count, word }) => `${count} ${word}\n`).join("");
  if (out.length > 0) process.stdout.write(out);
}

await main();
