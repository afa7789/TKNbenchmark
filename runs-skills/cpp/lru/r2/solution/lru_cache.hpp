#pragma once

#include <cstddef>
#include <list>
#include <optional>
#include <string>
#include <string_view>
#include <unordered_map>

// Fixed-capacity least-recently-used cache with O(1) expected operations.
class LruCache {
public:
    explicit LruCache(std::size_t capacity) : capacity_(capacity) {
        index_.reserve(capacity_ < kMaxReserve ? capacity_ + 1 : kMaxReserve);
    }

    // Inserts or overwrites; the key becomes most recently used.
    void set(std::string_view key, std::string_view value) {
        if (auto it = index_.find(key); it != index_.end()) {
            it->second->value.assign(value);
            touch(it->second);
            return;
        }
        entries_.push_front(Entry{std::string(key), std::string(value)});
        index_.emplace(entries_.front().key, entries_.begin());
        if (index_.size() > capacity_) {
            index_.erase(entries_.back().key);
            entries_.pop_back();
        }
    }

    // Returns the value on a hit and marks the key most recently used.
    [[nodiscard]] std::optional<std::string_view> get(std::string_view key) {
        auto it = index_.find(key);
        if (it == index_.end()) return std::nullopt;
        touch(it->second);
        return std::string_view(it->second->value);
    }

    // Removes the key; returns whether it was present.
    bool erase(std::string_view key) {
        auto it = index_.find(key);
        if (it == index_.end()) return false;
        auto node = it->second;
        index_.erase(it);
        entries_.erase(node);
        return true;
    }

    [[nodiscard]] std::size_t size() const noexcept { return index_.size(); }

private:
    struct Entry {
        std::string key;
        std::string value;
    };
    using List = std::list<Entry>;

    static constexpr std::size_t kMaxReserve = std::size_t{1} << 20;

    void touch(List::iterator node) { entries_.splice(entries_.begin(), entries_, node); }

    std::size_t capacity_;
    List entries_;  // front = most recently used
    // Keys view the strings owned by list nodes, which never move.
    std::unordered_map<std::string_view, List::iterator> index_;
};
