import Testing
@testable import LRUCore

@Suite struct LRUCacheTests {
    @Test func evictsLeastRecentlyUsed() {
        var cache = LRUCache<String, String>(capacity: 2)
        cache.set("a", "1")
        cache.set("b", "2")
        #expect(cache.get("a") == "1")
        cache.set("c", "3")
        #expect(cache.get("b") == nil)
        #expect(cache.count == 2)
    }

    @Test func overwriteRefreshesRecency() {
        var cache = LRUCache<String, String>(capacity: 2)
        cache.set("a", "1")
        cache.set("b", "2")
        cache.set("a", "9")
        cache.set("c", "3")
        #expect(cache.get("a") == "9")
        #expect(cache.get("b") == nil)
    }

    @Test func removeReportsPresenceAndReusesSlots() {
        var cache = LRUCache<String, String>(capacity: 3)
        cache.set("x", "1")
        #expect(cache.remove("x"))
        #expect(!cache.remove("x"))
        #expect(cache.count == 0)
        for i in 0..<10 { cache.set("k\(i)", "\(i)") }
        #expect(cache.count == 3)
        #expect(cache.get("k9") == "9")
        #expect(cache.get("k6") == nil)
    }

    @Test func processorFormatsOutput() {
        var p = CommandProcessor(capacity: 1)
        #expect(p.execute("SET a 1") == nil)
        #expect(p.execute("GET a") == "1")
        #expect(p.execute("GET b") == "NULL")
        #expect(p.execute("DEL a") == "1")
        #expect(p.execute("SIZE") == "0")
    }
}
