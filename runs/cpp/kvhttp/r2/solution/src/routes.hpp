#pragma once

#include "http.hpp"
#include "kv_store.hpp"

namespace kvhttp {

// Returns true if `key` matches [A-Za-z0-9_-]{1,64}.
bool is_valid_key(std::string_view key);

// Dispatches a request against the key-value API.
http::Response route(KvStore& store, const http::Request& request);

}  // namespace kvhttp
