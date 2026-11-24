#pragma once

#include <map>
#include <memory>
#include <mutex>
#include <optional>
#include <shared_mutex>
#include <string>
#include <string_view>
#include <vector>

namespace kvhttp {

// Thread-safe in-memory key/value store. Values are held by shared_ptr so
// readers can release the lock before the (possibly large) value is sent.
class KvStore {
public:
    using Value = std::shared_ptr<const std::string>;

    // Returns true if the key was newly inserted, false if it replaced a value.
    bool put(std::string key, std::string value) {
        auto v = std::make_shared<const std::string>(std::move(value));
        std::unique_lock lock(mutex_);
        auto [it, inserted] = map_.try_emplace(std::move(key), v);
        if (!inserted) it->second = std::move(v);
        return inserted;
    }

    [[nodiscard]] Value get(std::string_view key) const {
        std::shared_lock lock(mutex_);
        auto it = map_.find(key);
        return it == map_.end() ? nullptr : it->second;
    }

    bool erase(std::string_view key) {
        std::unique_lock lock(mutex_);
        auto it = map_.find(key);
        if (it == map_.end()) return false;
        map_.erase(it);
        return true;
    }

    // Keys in ascending (byte-wise) order.
    [[nodiscard]] std::vector<std::string> keys() const {
        std::shared_lock lock(mutex_);
        std::vector<std::string> out;
        out.reserve(map_.size());
        for (const auto& [k, _] : map_) out.push_back(k);
        return out;
    }

private:
    mutable std::shared_mutex mutex_;
    std::map<std::string, Value, std::less<>> map_;
};

}  // namespace kvhttp
