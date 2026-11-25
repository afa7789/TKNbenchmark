#pragma once

#include <cstddef>
#include <optional>
#include <string>
#include <string_view>
#include <utility>
#include <variant>
#include <vector>

namespace kvhttp {

inline constexpr std::size_t kMaxHeaderBytes = 64 * 1024;
inline constexpr std::size_t kMaxBodyBytes = 1024 * 1024;

struct RequestHead {
  std::string method;
  std::string target;
  std::string version;
  std::vector<std::pair<std::string, std::string>> headers;

  // Case-insensitive lookup of the first header with this name.
  [[nodiscard]] std::optional<std::string_view> header(std::string_view name) const;
};

struct Request {
  RequestHead head;
  std::string body;
};

struct Response {
  int status = 200;
  std::string body;
  std::string content_type;  // empty: no Content-Type header
  std::vector<std::pair<std::string, std::string>> extra_headers;

  [[nodiscard]] static Response empty(int status) { return Response{.status = status}; }
  [[nodiscard]] static Response text(int status, std::string body) {
    return Response{.status = status, .body = std::move(body), .content_type = "text/plain; charset=utf-8"};
  }
};

// An error found while reading a request; the connection answers with `status` and closes.
struct HttpError {
  int status;
  std::string message;
};

// Parses the request line and header fields (everything before the blank line,
// excluding the final CRLFCRLF).
[[nodiscard]] std::variant<RequestHead, HttpError> parse_request_head(std::string_view head);

// Determines the body length declared by the head, validating framing headers.
[[nodiscard]] std::variant<std::size_t, HttpError> body_length(const RequestHead& head);

[[nodiscard]] std::string_view reason_phrase(int status) noexcept;

// Serializes the status line, headers and body. Always includes Content-Length.
[[nodiscard]] std::string serialize(const Response& response);

}  // namespace kvhttp
