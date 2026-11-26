/*
 * lru — simulate an LRU cache driven by commands on standard input.
 *
 * The whole input is read into memory once; keys and values are stored as
 * (offset, length) slices into that buffer, so no per-entry allocation is
 * needed. Entries live in a preallocated node pool (struct-of-arrays) linked
 * into an intrusive doubly linked recency list and a chained hash table,
 * giving O(1) expected time per command.
 */
package lru

import java.io.OutputStream
import kotlin.system.exitProcess

private const val NIL = -1
private const val MAX_CAPACITY = 1_000_000L
private const val MAX_TOKEN_LENGTH = 255
private const val SPACE = ' '.code.toByte()
private const val NEWLINE = '\n'.code.toByte()
private const val CR = '\r'.code.toByte()

/** A half-open byte range `[start, end)` inside the shared input buffer. */
@JvmInline
private value class Slice(private val packed: Long) {
    constructor(start: Int, end: Int) : this((start.toLong() shl 32) or (end.toLong() and 0xffffffffL))

    val start: Int get() = (packed ushr 32).toInt()
    val end: Int get() = packed.toInt()
    val length: Int get() = end - start
    val isEmpty: Boolean get() = end <= start
}

/**
 * LRU cache over byte slices of [data]. At most [capacity] keys are held; the
 * node pool is sized to [maxNodes], which never needs to exceed the capacity.
 */
private class LruCache(private val data: ByteArray, private val capacity: Int, maxNodes: Int) {
    private val keyStart = IntArray(maxNodes)
    private val keyLen = IntArray(maxNodes)
    private val valStart = IntArray(maxNodes)
    private val valLen = IntArray(maxNodes)
    private val hashes = IntArray(maxNodes)
    private val prev = IntArray(maxNodes) // towards more recently used
    private val next = IntArray(maxNodes) // towards less recently used
    private val chain = IntArray(maxNodes) // next node in the same bucket, or free list

    private val buckets: IntArray
    private val mask: Int

    private var used = 0 // nodes ever handed out from the pool
    private var freeHead = NIL // recycled nodes
    private var head = NIL // most recently used
    private var tail = NIL // least recently used

    var size = 0
        private set

    init {
        var nb = 16
        while (nb < maxNodes.toLong() * 2) nb = nb shl 1
        buckets = IntArray(nb) { NIL }
        mask = nb - 1
    }

    /** Returns the value slice for [key] and marks it most recently used, or null on a miss. */
    fun get(key: Slice): Slice? {
        val i = find(key, hash(key))
        if (i == NIL) return null
        touch(i)
        return Slice(valStart[i], valStart[i] + valLen[i])
    }

    /** Removes [key]; returns whether it was present. */
    fun delete(key: Slice): Boolean = removeKey(key, hash(key))

    fun set(key: Slice, value: Slice) {
        val h = hash(key)
        var i = find(key, h)
        if (i != NIL) {
            valStart[i] = value.start
            valLen[i] = value.length
            touch(i)
            return
        }

        if (size == capacity) {
            val lru = tail
            removeKey(Slice(keyStart[lru], keyStart[lru] + keyLen[lru]), hashes[lru])
        }

        if (freeHead != NIL) {
            i = freeHead
            freeHead = chain[i]
        } else {
            i = used++
        }

        keyStart[i] = key.start
        keyLen[i] = key.length
        valStart[i] = value.start
        valLen[i] = value.length
        hashes[i] = h
        val b = h and mask
        chain[i] = buckets[b]
        buckets[b] = i
        pushFront(i)
        size++
    }

    /** FNV-1a with a final xor-shift to spread the high bits into the bucket mask. */
    private fun hash(s: Slice): Int {
        var h = -0x7ee3623b // 2166136261
        for (p in s.start until s.end) {
            h = (h xor (data[p].toInt() and 0xff)) * 16777619
        }
        return h xor (h ushr 15)
    }

    private fun matches(i: Int, key: Slice, h: Int): Boolean {
        if (hashes[i] != h || keyLen[i] != key.length) return false
        val ks = keyStart[i]
        return data.contentRangeEquals(ks, key.start, key.length)
    }

    private fun find(key: Slice, h: Int): Int {
        var i = buckets[h and mask]
        while (i != NIL && !matches(i, key, h)) i = chain[i]
        return i
    }

    /** Unlinks [key] from its bucket chain and the recency list, recycling its node. */
    private fun removeKey(key: Slice, h: Int): Boolean {
        val b = h and mask
        var before = NIL
        var i = buckets[b]
        while (i != NIL && !matches(i, key, h)) {
            before = i
            i = chain[i]
        }
        if (i == NIL) return false

        if (before == NIL) buckets[b] = chain[i] else chain[before] = chain[i]
        unlink(i)
        chain[i] = freeHead
        freeHead = i
        size--
        return true
    }

    private fun unlink(i: Int) {
        val p = prev[i]
        val n = next[i]
        if (p != NIL) next[p] = n else head = n
        if (n != NIL) prev[n] = p else tail = p
    }

    private fun pushFront(i: Int) {
        prev[i] = NIL
        next[i] = head
        if (head != NIL) prev[head] = i else tail = i
        head = i
    }

    private fun touch(i: Int) {
        if (head == i) return
        unlink(i)
        pushFront(i)
    }
}

private fun ByteArray.contentRangeEquals(a: Int, b: Int, length: Int): Boolean {
    for (k in 0 until length) {
        if (this[a + k] != this[b + k]) return false
    }
    return true
}

/** Growable output buffer written to the underlying stream once at the end. */
private class LineWriter(initialCapacity: Int = 1 shl 16) {
    private var buf = ByteArray(initialCapacity)
    private var len = 0

    private fun reserve(extra: Int) {
        if (buf.size - len >= extra) return
        var cap = buf.size
        while (cap - len < extra) cap *= 2
        buf = buf.copyOf(cap)
    }

    fun line(src: ByteArray, slice: Slice) {
        reserve(slice.length + 1)
        System.arraycopy(src, slice.start, buf, len, slice.length)
        len += slice.length
        buf[len++] = NEWLINE
    }

    fun line(text: String) {
        reserve(text.length + 1)
        for (c in text) buf[len++] = c.code.toByte()
        buf[len++] = NEWLINE
    }

    fun line(value: Int) = line(value.toString())

    fun writeTo(out: OutputStream) {
        out.write(buf, 0, len)
        out.flush()
    }
}

/** Sequential tokenizer over one line `[pos, end)` of [data], split on spaces. */
private class Tokens(private val data: ByteArray, private var pos: Int, private val end: Int) {
    fun next(): Slice {
        var s = pos
        while (s < end && data[s] == SPACE) s++
        var e = s
        while (e < end && data[e] != SPACE) e++
        pos = e
        return Slice(s, e)
    }
}

private fun Slice.equalsAscii(data: ByteArray, word: String): Boolean {
    if (length != word.length) return false
    for (k in word.indices) {
        if (data[start + k] != word[k].code.toByte()) return false
    }
    return true
}

private fun runCommand(cache: LruCache, data: ByteArray, out: LineWriter, line: Slice) {
    val tokens = Tokens(data, line.start, line.end)
    val cmd = tokens.next()
    if (cmd.isEmpty) return

    if (cmd.equalsAscii(data, "SIZE")) {
        out.line(cache.size)
        return
    }
    if (cmd.length != 3) return
    val key = tokens.next()
    if (key.isEmpty || key.length > MAX_TOKEN_LENGTH) return

    when {
        cmd.equalsAscii(data, "GET") -> {
            val value = cache.get(key)
            if (value != null) out.line(data, value) else out.line("NULL")
        }
        cmd.equalsAscii(data, "DEL") -> out.line(if (cache.delete(key)) "1" else "0")
        cmd.equalsAscii(data, "SET") -> {
            val value = tokens.next()
            if (!value.isEmpty && value.length <= MAX_TOKEN_LENGTH) cache.set(key, value)
        }
    }
}

/** Returns the line content starting at [from] (without `\n` or a trailing `\r`) and the next line's offset. */
private fun ByteArray.lineAt(from: Int): Pair<Slice, Int> {
    var nl = from
    while (nl < size && this[nl] != NEWLINE) nl++
    val next = if (nl < size) nl + 1 else size
    val end = if (nl > from && this[nl - 1] == CR) nl - 1 else nl
    return Slice(from, end) to next
}

/** Parses a leading integer like C's `strtol(s, NULL, 10)`: 0 if none, saturating on overflow. */
private fun parseLeadingLong(data: ByteArray, slice: Slice): Long {
    var p = slice.start
    val end = slice.end
    while (p < end && data[p].toInt().toChar() in " \t\n\u000B\u000C\r") p++
    var negative = false
    if (p < end && (data[p] == '+'.code.toByte() || data[p] == '-'.code.toByte())) {
        negative = data[p] == '-'.code.toByte()
        p++
    }
    var value = 0L
    while (p < end && data[p] in '0'.code.toByte()..'9'.code.toByte()) {
        val digit = data[p] - '0'.code.toByte()
        value = if (value > (Long.MAX_VALUE - digit) / 10) Long.MAX_VALUE else value * 10 + digit
        p++
    }
    return if (negative) -value else value
}

private fun countNewlines(data: ByteArray, from: Int): Int {
    var count = 0
    for (p in from until data.size) {
        if (data[p] == NEWLINE) count++
    }
    return count
}

fun main() {
    val data = try {
        System.`in`.readBytes()
    } catch (e: java.io.IOException) {
        System.err.println("lru: read error")
        exitProcess(1)
    }
    if (data.isEmpty()) return

    val (firstLine, bodyStart) = data.lineAt(0)
    // Like the original, only the first 31 bytes of the capacity line are considered.
    val capSlice = Slice(firstLine.start, minOf(firstLine.end, firstLine.start + 31))
    val capacity = parseLeadingLong(data, capSlice).coerceIn(1L, MAX_CAPACITY).toInt()

    // The pool never needs more nodes than the capacity or the number of remaining lines.
    val lines = countNewlines(data, bodyStart).toLong() + 1
    val maxNodes = minOf(capacity.toLong(), lines).toInt()

    val cache = LruCache(data, capacity, maxNodes)
    val out = LineWriter()

    var p = bodyStart
    while (p < data.size) {
        val (line, next) = data.lineAt(p)
        runCommand(cache, data, out, line)
        p = next
    }

    try {
        out.writeTo(System.out)
    } catch (e: java.io.IOException) {
        System.err.println("lru: write error")
        exitProcess(1)
    }
    if (System.out.checkError()) {
        System.err.println("lru: write error")
        exitProcess(1)
    }
}
