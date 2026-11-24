#pragma once

#include <cstddef>
#include <list>
#include <optional>
#include <string>
#include <string_view>
#include <unordered_map>
#include <utility>

// Fixed-capacity least-recently-used cache with O(1) expected-time operations.
//
// Entries live in a doubly linked list ordered from most to least recently
// used. The index maps keys to list nodes; its string_view keys point into the
// list nodes' own key strings, which stay put because list nodes never move.
class LruCache {
public:
    explicit LruCache(std::size_t capacity) : capacity_(capacity) {
        index_.reserve(capacity + 1);
    }

    // Inserts or overwrites `key`, making it the most recently used entry.
    // Evicts the least recently used entry if capacity is exceeded.
    void set(std::string_view key, std::string_view value) {
        if (auto it = index_.find(key); it != index_.end()) {
            it->second->value.assign(value);
            touch(it->second);
            return;
        }
        entries_.push_front(Entry{std::string(key), std::string(value)});
        index_.emplace(entries_.front().key, entries_.begin());
        if (index_.size() > capacity_) {
            evict_oldest();
        }
    }

    // Returns the value for `key` and marks it most recently used, or
    // std::nullopt on a miss. The view is valid until the next mutation.
    [[nodiscard]] std::optional<std::string_view> get(std::string_view key) {
        auto it = index_.find(key);
        if (it == index_.end()) {
            return std::nullopt;
        }
        touch(it->second);
        return std::string_view(it->second->value);
    }

    // Removes `key`; returns whether it was present.
    bool erase(std::string_view key) {
        auto it = index_.find(key);
        if (it == index_.end()) {
            return false;
        }
        auto node = it->second;
        index_.erase(it);  // erase first: the map key views the node's string
        entries_.erase(node);
        return true;
    }

    [[nodiscard]] std::size_t size() const noexcept { return index_.size(); }
    [[nodiscard]] std::size_t capacity() const noexcept { return capacity_; }

private:
    struct Entry {
        std::string key;
        std::string value;
    };
    using List = std::list<Entry>;

    void touch(List::iterator node) {
        entries_.splice(entries_.begin(), entries_, node);
    }

    void evict_oldest() {
        auto node = std::prev(entries_.end());
        index_.erase(std::string_view(node->key));
        entries_.erase(node);
    }

    std::size_t capacity_;
    List entries_;
    std::unordered_map<std::string_view, List::iterator> index_;
};
