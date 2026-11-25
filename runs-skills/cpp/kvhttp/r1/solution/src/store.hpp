#pragma once

#include <functional>
#include <map>
#include <optional>
#include <shared_mutex>
#include <string>
#include <string_view>
#include <vector>

namespace kvhttp {

// Thread-safe in-memory key-value store. Keys are kept ordered so listing is cheap.
class KvStore {
public:
    enum class PutResult { Created, Replaced };

    PutResult put(std::string key, std::string value);
    [[nodiscard]] std::optional<std::string> get(std::string_view key) const;
    bool erase(std::string_view key);
    [[nodiscard]] std::vector<std::string> keys() const;

private:
    mutable std::shared_mutex mutex_;
    std::map<std::string, std::string, std::less<>> data_;
};

}  // namespace kvhttp
