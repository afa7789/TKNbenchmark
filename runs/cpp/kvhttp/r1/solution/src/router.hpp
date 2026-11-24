#pragma once

#include "http.hpp"
#include "kv_store.hpp"

namespace kvhttp {

// Maps requests onto the key/value API described in SPEC.md.
class Router {
public:
    explicit Router(KvStore& store) : store_(store) {}

    [[nodiscard]] Response handle(Request& request) const;

private:
    [[nodiscard]] Response handle_key(Request& request, std::string_view key) const;
    [[nodiscard]] Response list_keys() const;

    KvStore& store_;
};

}  // namespace kvhttp
