/// A fixed-capacity least-recently-used cache.
///
/// Entries live in a contiguous node pool linked into a doubly linked list
/// ordered from most to least recently used; a dictionary maps keys to pool
/// slots. Every operation runs in O(1) expected time, and freed slots are
/// recycled so the pool never grows beyond `capacity + 1` nodes.
struct LRUCache<Key: Hashable, Value> {
    private struct Node {
        var key: Key
        var value: Value
        var prev: Int
        var next: Int
    }

    private static var none: Int { -1 }

    let capacity: Int
    private var nodes: [Node] = []
    private var slots: [Key: Int] = [:]
    private var freeSlots: [Int] = []
    private var head = LRUCache.none  // most recently used
    private var tail = LRUCache.none  // least recently used

    init(capacity: Int, reservingCapacity reserve: Int? = nil) {
        precondition(capacity > 0, "LRU capacity must be positive")
        self.capacity = capacity
        let initial = min(capacity + 1, reserve ?? capacity + 1)
        nodes.reserveCapacity(initial)
        slots.reserveCapacity(initial)
    }

    var count: Int { slots.count }

    /// Returns the value for `key`, marking it as most recently used on a hit.
    mutating func value(forKey key: Key) -> Value? {
        guard let slot = slots[key] else { return nil }
        moveToFront(slot)
        return nodes[slot].value
    }

    /// Inserts or overwrites `key`, making it the most recently used entry and
    /// evicting the least recently used entry if capacity is exceeded.
    mutating func setValue(_ value: Value, forKey key: Key) {
        if let slot = slots[key] {
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
        slots[key] = slot
        pushFront(slot)

        if slots.count > capacity {
            remove(slot: tail)
        }
    }

    /// Removes `key`, returning whether it was present.
    @discardableResult
    mutating func removeValue(forKey key: Key) -> Bool {
        guard let slot = slots[key] else { return false }
        remove(slot: slot)
        return true
    }

    // MARK: - Linked list maintenance

    private mutating func remove(slot: Int) {
        unlink(slot)
        slots.removeValue(forKey: nodes[slot].key)
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
