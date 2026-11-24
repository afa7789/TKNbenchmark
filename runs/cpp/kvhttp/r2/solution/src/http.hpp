#pragma once

#include <cstddef>
#include <optional>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace kvhttp::http {

struct Request {
    std::string method;
    std::string target;
    std::vector<std::pair<std::string, std::string>> headers;
    std::string body;

    // Case-insensitive header lookup; returns the first match.
    std::optional<std::string_view> header(std::string_view name) const;
};

struct Response {
    int status = 200;
    std::vector<std::pair<std::string, std::string>> headers;
    std::string body;

    static Response empty(int status) { return Response{status, {}, {}}; }
    static Response text(int status, std::string body) {
        return Response{status, {{"Content-Type", "text/plain; charset=utf-8"}}, std::move(body)};
    }

    // Serializes status line and headers, including Content-Length and
    // Connection: close. The body is not included.
    std::string serialize_head() const;
};

std::string_view reason_phrase(int status);

bool iequals(std::string_view a, std::string_view b);

// Result of parsing the request head (request line + headers).
struct ParsedHead {
    Request request;
    std::size_t head_size = 0;  // bytes consumed, including the final CRLFCRLF
};

// Parses a complete request head contained in `data` (which must contain the
// terminating blank line). Returns std::nullopt if the head is malformed.
std::optional<ParsedHead> parse_head(std::string_view data);

}  // namespace kvhttp::http
