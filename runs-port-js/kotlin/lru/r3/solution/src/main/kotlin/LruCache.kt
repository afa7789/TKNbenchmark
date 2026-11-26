/**
 * Fixed-capacity LRU cache backed by a hash map and an intrusive doubly
 * linked list stored in primitive arrays. Every operation is O(1) expected.
 */
class LruCache<K : Any, V : Any>(private val capacity: Int) {
    init {
        require(capacity >= 1) { "capacity must be positive, was $capacity" }
    }

    private val index = HashMap<K, Int>()
    private val keys = arrayOfNulls<Any>(capacity + 1)
    private val values = arrayOfNulls<Any>(capacity + 1)
    private val prev = IntArray(capacity + 1)
    private val next = IntArray(capacity + 1)
    private val freeSlots = IntArray(capacity + 1)
    private var freeCount = 0
    private var nextSlot = 0
    private var head = NIL // most recently used
    private var tail = NIL // least recently used

    val size: Int get() = index.size

    operator fun get(key: K): V? {
        val slot = index[key] ?: return null
        moveToFront(slot)
        return valueAt(slot)
    }

    operator fun set(key: K, value: V) {
        index[key]?.let { slot ->
            values[slot] = value
            moveToFront(slot)
            return
        }
        val slot = if (freeCount > 0) freeSlots[--freeCount] else nextSlot++
        keys[slot] = key
        values[slot] = value
        index[key] = slot
        pushFront(slot)
        if (index.size > capacity) removeSlot(tail)
    }

    /** Removes [key]; returns whether it was present. */
    fun remove(key: K): Boolean {
        val slot = index[key] ?: return false
        removeSlot(slot)
        return true
    }

    @Suppress("UNCHECKED_CAST")
    private fun valueAt(slot: Int): V = values[slot] as V

    private fun removeSlot(slot: Int) {
        unlink(slot)
        index.remove(keys[slot])
        keys[slot] = null
        values[slot] = null
        freeSlots[freeCount++] = slot
    }

    private fun pushFront(slot: Int) {
        prev[slot] = NIL
        next[slot] = head
        if (head != NIL) prev[head] = slot else tail = slot
        head = slot
    }

    private fun unlink(slot: Int) {
        val p = prev[slot]
        val n = next[slot]
        if (p != NIL) next[p] = n else head = n
        if (n != NIL) prev[n] = p else tail = p
    }

    private fun moveToFront(slot: Int) {
        if (slot == head) return
        unlink(slot)
        pushFront(slot)
    }

    private companion object {
        const val NIL = -1
    }
}
