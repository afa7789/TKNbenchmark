/// A fixed-capacity least-recently-used cache.
///
/// Entries live in contiguous storage and are threaded onto an intrusive
/// doubly linked list (ordered from most to least recently used) by index,
/// so every operation runs in O(1) expected time without per-node allocation.
struct LRUCache<Key: Hashable, Value> {
    private struct Node {
        var key: Key
        var value: Value
        var prev: Int
        var next: Int
    }

    private static var none: Int { -1 }

    let capacity: Int
    private var index: [Key: Int] = [:]
    private var nodes: [Node] = []
    private var freeSlots: [Int] = []
    private var head = LRUCache.none  // most recently used
    private var tail = LRUCache.none  // least recently used

    init(capacity: Int) {
        precondition(capacity > 0, "capacity must be positive")
        self.capacity = capacity
        let initial = min(capacity, 1 << 16)
        index.reserveCapacity(initial)
        nodes.reserveCapacity(initial)
    }

    var count: Int { index.count }

    /// Returns the value for `key`, marking it as most recently used.
    mutating func value(forKey key: Key) -> Value? {
        guard let slot = index[key] else { return nil }
        moveToFront(slot)
        return nodes[slot].value
    }

    /// Inserts or overwrites `key`, marking it as most recently used and
    /// evicting the least recently used entry if capacity is exceeded.
    mutating func setValue(_ value: Value, forKey key: Key) {
        if let slot = index[key] {
            nodes[slot].value = value
            moveToFront(slot)
            return
        }
        if index.count >= capacity {
            evictLeastRecentlyUsed()
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
    }

    /// Removes `key`, returning whether it was present.
    @discardableResult
    mutating func removeValue(forKey key: Key) -> Bool {
        guard let slot = index.removeValue(forKey: key) else { return false }
        unlink(slot)
        freeSlots.append(slot)
        return true
    }

    // MARK: - List maintenance

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
