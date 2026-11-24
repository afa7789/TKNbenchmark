/// A fixed-capacity least-recently-used cache with O(1) expected-time operations.
///
/// Entries live in a contiguous node pool linked into a doubly linked recency list
/// by index, so no per-entry heap allocation or reference counting is needed.
/// Slots freed by deletion are recycled through a free list.
struct LRUCache<Key: Hashable, Value> {
    private struct Node {
        var key: Key
        var value: Value
        var prev: Int
        var next: Int
    }

    private static var none: Int { -1 }

    let capacity: Int
    private var index: [Key: Int]
    private var nodes: [Node] = []
    private var freeSlots: [Int] = []
    /// Most recently used entry.
    private var head = LRUCache.none
    /// Least recently used entry.
    private var tail = LRUCache.none

    init(capacity: Int) {
        precondition(capacity > 0, "LRU capacity must be positive")
        self.capacity = capacity
        self.index = Dictionary(minimumCapacity: min(capacity, 1 << 16))
    }

    var count: Int { index.count }

    /// Returns the value for `key`, marking it most recently used on a hit.
    mutating func value(forKey key: Key) -> Value? {
        guard let slot = index[key] else { return nil }
        moveToFront(slot)
        return nodes[slot].value
    }

    /// Inserts or overwrites `key`, marking it most recently used and evicting
    /// the least recently used entry if the capacity is exceeded.
    mutating func setValue(_ value: Value, forKey key: Key) {
        if let slot = index[key] {
            nodes[slot].value = value
            moveToFront(slot)
            return
        }
        let node = Node(key: key, value: value, prev: Self.none, next: Self.none)
        let slot: Int
        if let reused = freeSlots.popLast() {
            nodes[reused] = node
            slot = reused
        } else {
            slot = nodes.count
            nodes.append(node)
        }
        index[key] = slot
        pushFront(slot)
        if index.count > capacity {
            evictLeastRecentlyUsed()
        }
    }

    /// Removes `key`, returning whether it was present.
    @discardableResult
    mutating func removeValue(forKey key: Key) -> Bool {
        guard let slot = index.removeValue(forKey: key) else { return false }
        unlink(slot)
        freeSlots.append(slot)
        return true
    }

    // MARK: - Recency list

    private mutating func evictLeastRecentlyUsed() {
        let slot = tail
        guard slot != Self.none else { return }
        index.removeValue(forKey: nodes[slot].key)
        unlink(slot)
        freeSlots.append(slot)
    }

    private mutating func moveToFront(_ slot: Int) {
        guard slot != head else { return }
        unlink(slot)
        pushFront(slot)
    }

    private mutating func pushFront(_ slot: Int) {
        nodes[slot].prev = Self.none
        nodes[slot].next = head
        if head != Self.none {
            nodes[head].prev = slot
        } else {
            tail = slot
        }
        head = slot
    }

    private mutating func unlink(_ slot: Int) {
        let prev = nodes[slot].prev
        let next = nodes[slot].next
        if prev != Self.none {
            nodes[prev].next = next
        } else {
            head = next
        }
        if next != Self.none {
            nodes[next].prev = prev
        } else {
            tail = prev
        }
        nodes[slot].prev = Self.none
        nodes[slot].next = Self.none
    }
}
