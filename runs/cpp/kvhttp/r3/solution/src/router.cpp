#include "router.hpp"

#include <algorithm>

namespace kvhttp {
namespace {

constexpr std::string_view kKvPrefix = "/kv/";
constexpr std::size_t kMaxKeyLength = 64;

Response status_only(int status) { return Response{.status = status}; }

// Keys are restricted to [A-Za-z0-9_-], so no JSON escaping is ever required.
std::string json_string_array(const std::vector<std::string>& items) {
    std::size_t size = 2;
    for (const auto& item : items) size += item.size() + 3;
    std::string out;
    out.reserve(size);
    out += '[';
    for (std::size_t i = 0; i < items.size(); ++i) {
        if (i) out += ',';
        out += '"';
        out += items[i];
        out += '"';
    }
    out += ']';
    return out;
}

}  // namespace

bool is_valid_key(std::string_view key) {
    if (key.empty() || key.size() > kMaxKeyLength) return false;
    return std::ranges::all_of(key, [](char c) {
        return (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') ||
               c == '_' || c == '-';
    });
}

Response Router::handle(Request& request) {
    const std::string_view path = request.target;

    if (path == "/health") {
        if (request.method != "GET") return status_only(405);
        return Response{.status = 200, .content_type = "text/plain", .body = "ok"};
    }

    if (path == "/kv") {
        if (request.method != "GET") return status_only(405);
        return Response{.status = 200,
                        .content_type = "application/json",
                        .body = json_string_array(store_.keys())};
    }

    if (path.starts_with(kKvPrefix)) {
        const std::string_view key = path.substr(kKvPrefix.size());
        if (!is_valid_key(key)) return status_only(400);
        return handle_key(request, std::string(key));
    }

    return status_only(404);
}

Response Router::handle_key(Request& request, const std::string& key) {
    if (request.method == "GET") {
        auto value = store_.get(key);
        if (!value) return status_only(404);
        return Response{.status = 200, .content_type = "application/octet-stream", .body = *value};
    }
    if (request.method == "PUT") {
        const bool created = store_.put(key, std::move(request.body));
        return status_only(created ? 201 : 200);
    }
    if (request.method == "DELETE") {
        return status_only(store_.erase(key) ? 204 : 404);
    }
    return status_only(405);
}

}  // namespace kvhttp
