#include "router.hpp"

#include <algorithm>
#include <utility>

namespace kvhttp {
namespace {

constexpr std::string_view kKeyPrefix = "/kv/";

Response status_only(int status) { return Response{.status = status, .content_type = {}, .body = {}}; }

std::string keys_as_json(const std::vector<std::string>& keys) {
    std::size_t size = 2;
    for (const auto& key : keys) size += key.size() + 3;
    std::string out;
    out.reserve(size);
    out += '[';
    for (bool first = true; const auto& key : keys) {
        if (!first) out += ',';
        first = false;
        // Valid keys contain no characters that need JSON escaping.
        out += '"';
        out += key;
        out += '"';
    }
    out += ']';
    return out;
}

}  // namespace

bool is_valid_key(std::string_view key) noexcept {
    return !key.empty() && key.size() <= 64 && std::ranges::all_of(key, [](char c) {
        return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
               c == '_' || c == '-';
    });
}

Response Router::handle(Request request) const {
    const std::string_view target = request.target;
    const std::string_view method = request.method;

    if (target == "/health") {
        if (method != "GET") return status_only(405);
        return Response{.status = 200, .content_type = "text/plain", .body = "ok"};
    }
    if (target == "/kv") {
        if (method != "GET") return status_only(405);
        return Response{.status = 200,
                        .content_type = "application/json",
                        .body = keys_as_json(store_.keys())};
    }
    if (target.starts_with(kKeyPrefix)) {
        const auto key = target.substr(kKeyPrefix.size());
        if (!is_valid_key(key)) return status_only(400);
        return handle_key(request, key, std::move(request.body));
    }
    return status_only(404);
}

Response Router::handle_key(const Request& request, std::string_view key,
                            std::string&& body) const {
    const std::string_view method = request.method;
    if (method == "GET") {
        auto value = store_.get(key);
        if (!value) return status_only(404);
        return Response{.status = 200,
                        .content_type = "application/octet-stream",
                        .body = std::move(*value)};
    }
    if (method == "PUT") {
        const auto result = store_.put(std::string(key), std::move(body));
        return status_only(result == KvStore::PutResult::Created ? 201 : 200);
    }
    if (method == "DELETE") return status_only(store_.erase(key) ? 204 : 404);
    return status_only(405);
}

}  // namespace kvhttp
