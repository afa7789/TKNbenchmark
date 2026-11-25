#include "kvhttp/kv_store.hpp"

#include <mutex>
#include <utility>

namespace kvhttp {

KvStore::PutResult KvStore::put(std::string_view key, std::string value) {
    std::unique_lock lock(mutex_);
    if (const auto it = data_.find(key); it != data_.end()) {
        // Swap so the old value is freed after the lock is released.
        std::swap(it->second, value);
        lock.unlock();
        return PutResult::replaced;
    }
    data_.emplace(std::string(key), std::move(value));
    return PutResult::created;
}

std::optional<std::string> KvStore::get(std::string_view key) const {
    std::shared_lock lock(mutex_);
    if (const auto it = data_.find(key); it != data_.end()) return it->second;
    return std::nullopt;
}

bool KvStore::erase(std::string_view key) {
    std::unique_lock lock(mutex_);
    const auto it = data_.find(key);
    if (it == data_.end()) return false;
    data_.erase(it);
    return true;
}

std::vector<std::string> KvStore::keys() const {
    std::shared_lock lock(mutex_);
    std::vector<std::string> out;
    out.reserve(data_.size());
    for (const auto& [key, value] : data_) out.push_back(key);
    return out;
}

}  // namespace kvhttp
