#include "router.hpp"

#include <algorithm>
#include <string>

namespace kvhttp {
namespace {

constexpr std::string_view kKeyPrefix = "/kv/";
constexpr std::size_t kMaxKeyLength = 64;

Response method_not_allowed(std::string allow) {
  Response response = Response::empty(405);
  response.extra_headers.emplace_back("Allow", std::move(allow));
  return response;
}

}  // namespace

bool is_valid_key(std::string_view key) noexcept {
  if (key.empty() || key.size() > kMaxKeyLength) return false;
  return std::ranges::all_of(key, [](char c) {
    return (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '_' || c == '-';
  });
}

Response Router::handle(Request request) const {
  const std::string_view method = request.head.method;
  const std::string_view path = request.head.target;

  if (path == "/health") {
    if (method != "GET") return method_not_allowed("GET");
    return Response::text(200, "ok");
  }
  if (path == "/kv") {
    if (method != "GET") return method_not_allowed("GET");
    return list_keys();
  }
  if (path.starts_with(kKeyPrefix)) {
    const std::string_view key = path.substr(kKeyPrefix.size());
    if (!is_valid_key(key)) return Response::text(400, "invalid key");
    return handle_key(method, key, std::move(request.body));
  }
  return Response::text(404, "not found");
}

Response Router::handle_key(std::string_view method, std::string_view key, std::string body) const {
  if (method == "GET") {
    auto value = store_.get(key);
    if (!value) return Response::text(404, "not found");
    return Response{.status = 200, .body = *value, .content_type = "application/octet-stream"};
  }
  if (method == "PUT") {
    const bool created = store_.put(std::string(key), std::move(body));
    return Response::empty(created ? 201 : 200);
  }
  if (method == "DELETE") {
    return Response::empty(store_.erase(key) ? 204 : 404);
  }
  return method_not_allowed("GET, PUT, DELETE");
}

Response Router::list_keys() const {
  const auto keys = store_.keys();
  std::string json = "[";
  for (const auto& key : keys) {
    if (json.size() > 1) json += ',';
    // Valid keys contain only [A-Za-z0-9_-], so no JSON escaping is needed.
    json += '"';
    json += key;
    json += '"';
  }
  json += ']';
  return Response{.status = 200, .body = std::move(json), .content_type = "application/json"};
}

}  // namespace kvhttp
