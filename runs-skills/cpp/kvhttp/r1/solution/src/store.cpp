#include "store.hpp"

#include <mutex>
#include <utility>

namespace kvhttp {

KvStore::PutResult KvStore::put(std::string key, std::string value) {
    std::unique_lock lock(mutex_);
    auto [it, inserted] = data_.try_emplace(std::move(key), std::move(value));
    if (inserted) return PutResult::Created;
    it->second = std::move(value);  // try_emplace leaves `value` untouched on failure
    return PutResult::Replaced;
}

std::optional<std::string> KvStore::get(std::string_view key) const {
    std::shared_lock lock(mutex_);
    if (auto it = data_.find(key); it != data_.end()) return it->second;
    return std::nullopt;
}

bool KvStore::erase(std::string_view key) {
    std::unique_lock lock(mutex_);
    auto it = data_.find(key);
    if (it == data_.end()) return false;
    data_.erase(it);
    return true;
}

std::vector<std::string> KvStore::keys() const {
    std::shared_lock lock(mutex_);
    std::vector<std::string> result;
    result.reserve(data_.size());
    for (const auto& [key, value] : data_) result.push_back(key);
    return result;
}

}  // namespace kvhttp
