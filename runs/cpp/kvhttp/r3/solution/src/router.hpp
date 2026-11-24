#pragma once

#include "http.hpp"
#include "store.hpp"

namespace kvhttp {

// Maps requests onto the key/value API.
class Router {
public:
    explicit Router(Store& store) : store_(store) {}

    Response handle(Request& request);

private:
    Response handle_key(Request& request, const std::string& key);

    Store& store_;
};

// True if `key` matches [A-Za-z0-9_-]{1,64}.
bool is_valid_key(std::string_view key);

}  // namespace kvhttp
