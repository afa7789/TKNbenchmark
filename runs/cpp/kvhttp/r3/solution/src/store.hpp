#pragma once

#include <map>
#include <memory>
#include <mutex>
#include <optional>
#include <shared_mutex>
#include <string>
#include <vector>

namespace kvhttp {

// Thread-safe in-memory key/value store. Values are held behind shared_ptr so
// readers can release the lock before copying large values onto the wire.
class Store {
public:
    using Value = std::shared_ptr<const std::string>;

    // Returns true if the key was newly created, false if it replaced a value.
    bool put(const std::string& key, std::string value) {
        auto ptr = std::make_shared<const std::string>(std::move(value));
        std::unique_lock lock(mutex_);
        auto [it, inserted] = data_.try_emplace(key, ptr);
        if (!inserted) it->second = std::move(ptr);
        return inserted;
    }

    [[nodiscard]] Value get(const std::string& key) const {
        std::shared_lock lock(mutex_);
        auto it = data_.find(key);
        return it == data_.end() ? nullptr : it->second;
    }

    bool erase(const std::string& key) {
        std::unique_lock lock(mutex_);
        return data_.erase(key) > 0;
    }

    // Keys in ascending byte order.
    [[nodiscard]] std::vector<std::string> keys() const {
        std::shared_lock lock(mutex_);
        std::vector<std::string> out;
        out.reserve(data_.size());
        for (const auto& [k, _] : data_) out.push_back(k);
        return out;
    }

private:
    mutable std::shared_mutex mutex_;
    std::map<std::string, Value, std::less<>> data_;
};

}  // namespace kvhttp
