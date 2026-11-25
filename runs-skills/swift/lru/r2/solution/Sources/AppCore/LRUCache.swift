/// A fixed-capacity least-recently-used cache.
///
/// Entries live in a contiguous node pool linked into a doubly linked
/// recency list by index, and a dictionary maps keys to pool slots, so every
/// operation runs in O(1) expected time without per-entry allocations.
public struct LRUCache<Key: Hashable, Value> {
    private struct Node {
        var key: Key
        var value: Value
        var prev: Int
        var next: Int
    }

    private static var none: Int { -1 }

    public let capacity: Int
    private var index: [Key: Int] = [:]
    private var nodes: [Node] = []
    private var freeSlots: [Int] = []
    /// Most recently used node.
    private var head = LRUCache.none
    /// Least recently used node.
    private var tail = LRUCache.none

    public init(capacity: Int) {
        precondition(capacity > 0, "LRU capacity must be positive")
        self.capacity = capacity
        // Pre-size storage (bounded, so huge capacities stay lazy) to avoid
        // repeated rehashing and reallocation as the cache fills.
        let initial = Swift.min(capacity, 1 << 16)
        index.reserveCapacity(initial)
        nodes.reserveCapacity(initial)
    }

    public var count: Int { index.count }

    /// Returns the value for `key`, marking it as the most recently used.
    public mutating func value(forKey key: Key) -> Value? {
        guard let slot = index[key] else { return nil }
        moveToFront(slot)
        return nodes[slot].value
    }

    /// Inserts or overwrites `key`, marking it most recently used and evicting
    /// the least recently used entry if the capacity is exceeded.
    public mutating func setValue(_ value: Value, forKey key: Key) {
        if let slot = index[key] {
            nodes[slot].value = value
            moveToFront(slot)
            return
        }

        let slot: Int
        if index.count >= capacity {
            // Recycle the evicted node's slot for the new entry.
            slot = tail
            unlink(slot)
            index[nodes[slot].key] = nil
            nodes[slot] = Node(key: key, value: value, prev: Self.none, next: Self.none)
        } else if let reused = freeSlots.popLast() {
            slot = reused
            nodes[slot] = Node(key: key, value: value, prev: Self.none, next: Self.none)
        } else {
            slot = nodes.count
            nodes.append(Node(key: key, value: value, prev: Self.none, next: Self.none))
        }
        index[key] = slot
        pushFront(slot)
    }

    /// Removes `key`, returning whether it was present.
    @discardableResult
    public mutating func removeValue(forKey key: Key) -> Bool {
        guard let slot = index.removeValue(forKey: key) else { return false }
        unlink(slot)
        freeSlots.append(slot)
        return true
    }

    // MARK: - Recency list

    private mutating func moveToFront(_ slot: Int) {
        guard slot != head else { return }
        unlink(slot)
        pushFront(slot)
    }

    private mutating func pushFront(_ slot: Int) {
        nodes[slot].prev = Self.none
        nodes[slot].next = head
        if head != Self.none { nodes[head].prev = slot }
        head = slot
        if tail == Self.none { tail = slot }
    }

    private mutating func unlink(_ slot: Int) {
        let prev = nodes[slot].prev
        let next = nodes[slot].next
        if prev != Self.none { nodes[prev].next = next } else { head = next }
        if next != Self.none { nodes[next].prev = prev } else { tail = prev }
        nodes[slot].prev = Self.none
        nodes[slot].next = Self.none
    }
}
