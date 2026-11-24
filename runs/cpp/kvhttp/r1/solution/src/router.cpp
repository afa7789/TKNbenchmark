#include "router.hpp"

#include <algorithm>
#include <string_view>

namespace kvhttp {

namespace {

constexpr std::string_view kKvPrefix = "/kv/";
constexpr std::size_t kMaxKeyLength = 64;

bool is_valid_key(std::string_view key) {
    if (key.empty() || key.size() > kMaxKeyLength) return false;
    return std::ranges::all_of(key, [](char c) {
        return (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') ||
               c == '_' || c == '-';
    });
}

Response method_not_allowed(std::string allow) {
    Response r = Response::empty(405);
    r.headers.emplace_back("Allow", std::move(allow));
    return r;
}

}  // namespace

Response Router::handle(Request& request) const {
    const std::string_view path = request.target;

    if (path == "/health") {
        if (request.method != "GET") return method_not_allowed("GET");
        return Response::make(200, "ok");
    }
    if (path == "/kv") {
        if (request.method != "GET") return method_not_allowed("GET");
        return list_keys();
    }
    if (path.starts_with(kKvPrefix)) {
        const std::string_view key = path.substr(kKvPrefix.size());
        if (!is_valid_key(key)) return Response::empty(400);
        return handle_key(request, key);
    }
    return Response::empty(404);
}

Response Router::handle_key(Request& request, std::string_view key) const {
    if (request.method == "GET") {
        auto value = store_.get(key);
        if (!value) return Response::empty(404);
        Response r;
        r.status = 200;
        r.headers.emplace_back("Content-Type", "application/octet-stream");
        r.body = std::move(value);
        return r;
    }
    if (request.method == "PUT") {
        const bool created = store_.put(std::string(key), std::move(request.body));
        return Response::empty(created ? 201 : 200);
    }
    if (request.method == "DELETE") {
        return Response::empty(store_.erase(key) ? 204 : 404);
    }
    return method_not_allowed("GET, PUT, DELETE");
}

Response Router::list_keys() const {
    // Keys are restricted to [A-Za-z0-9_-], so no JSON escaping is needed.
    std::string json = "[";
    bool first = true;
    for (const auto& key : store_.keys()) {
        if (!first) json += ',';
        first = false;
        json += '"';
        json += key;
        json += '"';
    }
    json += ']';
    return Response::make(200, std::move(json), "application/json");
}

}  // namespace kvhttp
