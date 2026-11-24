#include "routes.hpp"

#include <algorithm>
#include <string>
#include <string_view>

namespace kvhttp {

namespace {

constexpr std::string_view kKvPrefix = "/kv/";
constexpr std::size_t kMaxKeyLength = 64;

http::Response method_not_allowed(std::string allow) {
    auto response = http::Response::text(405, "Method Not Allowed");
    response.headers.emplace_back("Allow", std::move(allow));
    return response;
}

http::Response handle_health(const http::Request& request) {
    if (request.method != "GET") {
        return method_not_allowed("GET");
    }
    return http::Response::text(200, "ok");
}

http::Response handle_list(KvStore& store, const http::Request& request) {
    if (request.method != "GET") {
        return method_not_allowed("GET");
    }
    // Keys are restricted to [A-Za-z0-9_-], so no JSON escaping is required.
    std::string body = "[";
    bool first = true;
    for (const auto& key : store.keys()) {
        if (!first) {
            body += ',';
        }
        first = false;
        body += '"';
        body += key;
        body += '"';
    }
    body += ']';
    return http::Response{200, {{"Content-Type", "application/json"}}, std::move(body)};
}

http::Response handle_key(KvStore& store, const http::Request& request, std::string_view key) {
    if (!is_valid_key(key)) {
        return http::Response::text(400, "invalid key");
    }
    if (request.method == "GET") {
        if (auto value = store.get(key)) {
            return http::Response{200, {{"Content-Type", "application/octet-stream"}}, std::move(*value)};
        }
        return http::Response::text(404, "not found");
    }
    if (request.method == "PUT") {
        const auto result = store.put(std::string(key), request.body);
        return http::Response::empty(result == KvStore::PutResult::Created ? 201 : 200);
    }
    if (request.method == "DELETE") {
        return store.erase(key) ? http::Response::empty(204) : http::Response::text(404, "not found");
    }
    return method_not_allowed("GET, PUT, DELETE");
}

}  // namespace

bool is_valid_key(std::string_view key) {
    return !key.empty() && key.size() <= kMaxKeyLength &&
           std::all_of(key.begin(), key.end(), [](char c) {
               return (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') ||
                      (c >= '0' && c <= '9') || c == '_' || c == '-';
           });
}

http::Response route(KvStore& store, const http::Request& request) {
    const std::string_view path = request.target;
    if (path == "/health") {
        return handle_health(request);
    }
    if (path == "/kv") {
        return handle_list(store, request);
    }
    if (path.starts_with(kKvPrefix)) {
        return handle_key(store, request, path.substr(kKvPrefix.size()));
    }
    return http::Response::text(404, "not found");
}

}  // namespace kvhttp
