/// A fixed-capacity cache that evicts the least recently used entry.
///
/// Entries live in a contiguous node pool linked into a doubly linked
/// recency list by index, so every operation runs in O(1) expected time
/// without per-entry heap allocations for the list itself.
public struct LRUCache<Key: Hashable, Value> {
    private struct Node {
        var key: Key
        var value: Value
        var prev: Int
        var next: Int
    }

    private static var none: Int { -1 }

    public let capacity: Int
    private var nodes: [Node] = []
    private var freeSlots: [Int] = []
    private var index: [Key: Int] = [:]
    /// Most recently used node.
    private var head = LRUCache.none
    /// Least recently used node.
    private var tail = LRUCache.none

    /// Creates an empty cache. `capacity` must be at least 1.
    public init(capacity: Int) {
        precondition(capacity >= 1, "LRUCache capacity must be at least 1")
        self.capacity = capacity
        let initial = Swift.min(capacity, 1 << 16)
        nodes.reserveCapacity(initial)
        index.reserveCapacity(initial)
    }

    /// The number of entries currently held.
    public var count: Int { index.count }

    /// Returns the value for `key`, marking it most recently used on a hit.
    public mutating func get(_ key: Key) -> Value? {
        guard let slot = index[key] else { return nil }
        moveToFront(slot)
        return nodes[slot].value
    }

    /// Inserts or overwrites `key`, marking it most recently used and
    /// evicting the least recently used entry if capacity is exceeded.
    public mutating func set(_ key: Key, _ value: Value) {
        if let slot = index[key] {
            nodes[slot].value = value
            moveToFront(slot)
            return
        }
        let slot = allocate(Node(key: key, value: value, prev: Self.none, next: Self.none))
        index[key] = slot
        linkAtFront(slot)
        if index.count > capacity {
            remove(slot: tail)
        }
    }

    /// Removes `key`. Returns `true` if it was present.
    @discardableResult
    public mutating func remove(_ key: Key) -> Bool {
        guard let slot = index[key] else { return false }
        remove(slot: slot)
        return true
    }

    // MARK: - Private

    private mutating func allocate(_ node: Node) -> Int {
        if let slot = freeSlots.popLast() {
            nodes[slot] = node
            return slot
        }
        nodes.append(node)
        return nodes.count - 1
    }

    private mutating func remove(slot: Int) {
        unlink(slot)
        index.removeValue(forKey: nodes[slot].key)
        freeSlots.append(slot)
    }

    private mutating func moveToFront(_ slot: Int) {
        guard slot != head else { return }
        unlink(slot)
        linkAtFront(slot)
    }

    private mutating func linkAtFront(_ slot: Int) {
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
