#pragma once

#include "http.hpp"
#include "store.hpp"

namespace kvhttp {

// Maps requests to the key-value API.
class Router {
public:
    explicit Router(KvStore& store) noexcept : store_(store) {}

    [[nodiscard]] Response handle(Request request) const;

private:
    [[nodiscard]] Response handle_key(const Request& request, std::string_view key,
                                      std::string&& body) const;

    KvStore& store_;
};

[[nodiscard]] bool is_valid_key(std::string_view key) noexcept;

}  // namespace kvhttp
