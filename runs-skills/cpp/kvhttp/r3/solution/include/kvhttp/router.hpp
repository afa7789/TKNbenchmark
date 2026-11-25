#pragma once

#include <string_view>

#include "kvhttp/http.hpp"
#include "kvhttp/kv_store.hpp"

namespace kvhttp {

// True if `key` matches [A-Za-z0-9_-]{1,64}.
[[nodiscard]] bool is_valid_key(std::string_view key) noexcept;

// Maps a request onto the key-value API.
class Router {
public:
    explicit Router(KvStore& store) noexcept : store_(store) {}
    [[nodiscard]] Response handle(Request req) const;

private:
    [[nodiscard]] Response handle_key(Request& req, std::string_view key) const;
    [[nodiscard]] Response list_keys() const;

    KvStore& store_;
};

}  // namespace kvhttp
