#pragma once

#include <map>
#include <mutex>
#include <optional>
#include <shared_mutex>
#include <string>
#include <string_view>
#include <vector>

namespace kvhttp {

// Thread-safe in-memory key-value store. Keys are kept ordered so that
// listing them sorted is a linear walk.
class KvStore {
public:
    enum class PutResult { Created, Replaced };

    PutResult put(std::string key, std::string value) {
        std::unique_lock lock(mutex_);
        auto [it, inserted] = data_.try_emplace(std::move(key), std::move(value));
        if (!inserted) {
            it->second = std::move(value);
            return PutResult::Replaced;
        }
        return PutResult::Created;
    }

    std::optional<std::string> get(std::string_view key) const {
        std::shared_lock lock(mutex_);
        if (auto it = data_.find(key); it != data_.end()) {
            return it->second;
        }
        return std::nullopt;
    }

    bool erase(std::string_view key) {
        std::unique_lock lock(mutex_);
        auto it = data_.find(key);
        if (it == data_.end()) {
            return false;
        }
        data_.erase(it);
        return true;
    }

    std::vector<std::string> keys() const {
        std::shared_lock lock(mutex_);
        std::vector<std::string> out;
        out.reserve(data_.size());
        for (const auto& [key, _] : data_) {
            out.push_back(key);
        }
        return out;
    }

private:
    mutable std::shared_mutex mutex_;
    std::map<std::string, std::string, std::less<>> data_;
};

}  // namespace kvhttp
