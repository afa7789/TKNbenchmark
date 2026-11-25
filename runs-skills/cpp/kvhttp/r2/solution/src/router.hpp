#pragma once

#include <string_view>

#include "http.hpp"
#include "kv_store.hpp"

namespace kvhttp {

// A key matches [A-Za-z0-9_-]{1,64}.
[[nodiscard]] bool is_valid_key(std::string_view key) noexcept;

// Maps a complete request onto the key-value API.
class Router {
 public:
  explicit Router(KvStore& store) noexcept : store_(store) {}

  [[nodiscard]] Response handle(Request request) const;

 private:
  [[nodiscard]] Response handle_key(std::string_view method, std::string_view key, std::string body) const;
  [[nodiscard]] Response list_keys() const;

  KvStore& store_;
};

}  // namespace kvhttp
