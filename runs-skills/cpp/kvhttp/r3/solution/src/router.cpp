#include "kvhttp/router.hpp"

#include <algorithm>
#include <cstddef>
#include <string>
#include <utility>

namespace kvhttp {
namespace {

constexpr std::size_t max_key_length = 64;
constexpr std::string_view kv_prefix = "/kv/";

Response method_not_allowed(std::string allow) {
    Response res = Response::empty(405);
    res.headers.push_back({"Allow", std::move(allow)});
    return res;
}

}  // namespace

bool is_valid_key(std::string_view key) noexcept {
    return !key.empty() && key.size() <= max_key_length && std::ranges::all_of(key, [](char c) {
        return (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '_' || c == '-';
    });
}

Response Router::handle(Request req) const {
    const std::string_view path = req.path;
    if (path == "/health") {
        if (req.method != "GET") return method_not_allowed("GET");
        return Response::text(200, "ok");
    }
    if (path == "/kv") {
        if (req.method != "GET") return method_not_allowed("GET");
        return list_keys();
    }
    if (path.starts_with(kv_prefix)) {
        const auto key = path.substr(kv_prefix.size());
        if (!is_valid_key(key)) return Response::text(400, "invalid key");
        return handle_key(req, key);
    }
    return Response::text(404, "not found");
}

Response Router::handle_key(Request& req, std::string_view key) const {
    if (req.method == "GET") {
        auto value = store_.get(key);
        if (!value) return Response::text(404, "not found");
        return Response::binary(200, std::move(*value));
    }
    if (req.method == "PUT") {
        const auto result = store_.put(key, std::move(req.body));
        return Response::empty(result == KvStore::PutResult::created ? 201 : 200);
    }
    if (req.method == "DELETE") {
        return Response::empty(store_.erase(key) ? 204 : 404);
    }
    return method_not_allowed("GET, PUT, DELETE");
}

Response Router::list_keys() const {
    // Keys are restricted to [A-Za-z0-9_-], so they never need JSON escaping.
    std::string body = "[";
    bool first = true;
    for (const auto& key : store_.keys()) {
        if (!first) body += ',';
        first = false;
        body += '"';
        body += key;
        body += '"';
    }
    body += ']';
    return Response::json(200, std::move(body));
}

}  // namespace kvhttp
