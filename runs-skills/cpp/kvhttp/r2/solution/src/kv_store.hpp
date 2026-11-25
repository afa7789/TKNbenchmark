#pragma once

#include <map>
#include <memory>
#include <mutex>
#include <shared_mutex>
#include <string>
#include <string_view>
#include <vector>

namespace kvhttp {

// Thread-safe in-memory key-value store. Values are immutable once stored and
// shared by pointer, so readers never copy large values while holding the lock.
class KvStore {
 public:
  using Value = std::shared_ptr<const std::string>;

  // Returns true if the key was newly created, false if an existing value was replaced.
  bool put(std::string key, std::string value) {
    auto stored = std::make_shared<const std::string>(std::move(value));
    std::unique_lock lock(mutex_);
    auto [it, inserted] = map_.try_emplace(std::move(key), stored);
    if (!inserted) it->second = std::move(stored);
    return inserted;
  }

  [[nodiscard]] Value get(std::string_view key) const {
    std::shared_lock lock(mutex_);
    auto it = map_.find(key);
    return it == map_.end() ? nullptr : it->second;
  }

  // Returns true if the key existed.
  bool erase(std::string_view key) {
    std::unique_lock lock(mutex_);
    auto it = map_.find(key);
    if (it == map_.end()) return false;
    map_.erase(it);
    return true;
  }

  // All keys in ascending byte order.
  [[nodiscard]] std::vector<std::string> keys() const {
    std::shared_lock lock(mutex_);
    std::vector<std::string> out;
    out.reserve(map_.size());
    for (const auto& [key, value] : map_) out.push_back(key);
    return out;
  }

 private:
  mutable std::shared_mutex mutex_;
  std::map<std::string, Value, std::less<>> map_;
};

}  // namespace kvhttp
