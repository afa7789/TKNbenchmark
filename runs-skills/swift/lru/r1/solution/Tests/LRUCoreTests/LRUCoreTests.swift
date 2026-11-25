import Testing
@testable import LRUCore

@Suite struct LRUCacheTests {
    @Test func evictsLeastRecentlyUsed() {
        var cache = LRUCache<String, Int>(capacity: 2)
        cache.set("a", 1)
        cache.set("b", 2)
        #expect(cache.get("a") == 1)
        cache.set("c", 3)
        #expect(cache.get("b") == nil)
        #expect(cache.count == 2)
    }

    @Test func overwriteRefreshesRecency() {
        var cache = LRUCache<String, Int>(capacity: 2)
        cache.set("a", 1)
        cache.set("b", 2)
        cache.set("a", 9)
        cache.set("c", 3)
        #expect(cache.get("a") == 9)
        #expect(cache.get("b") == nil)
    }

    @Test func removeReportsPresenceAndReusesSlots() {
        var cache = LRUCache<String, Int>(capacity: 1)
        cache.set("x", 1)
        #expect(cache.remove("x"))
        #expect(!cache.remove("x"))
        #expect(cache.count == 0)
        cache.set("y", 2)
        #expect(cache.get("y") == 2)
    }
}

@Suite struct CommandProcessorTests {
    @Test func specExample() {
        let input = "2\nSET a 1\nSET b 2\nGET a\nSET c 3\nGET b\nSIZE"
        let output = CommandProcessor.run(lines: input.split(separator: "\n", omittingEmptySubsequences: false))
        #expect(output == "1\nNULL\n2\n")
    }
}
