#pragma once

#include <cstddef>
#include <optional>
#include <string>
#include <string_view>

namespace kvhttp {

inline constexpr std::size_t kMaxHeadSize = 16 * 1024;
inline constexpr std::size_t kMaxBodySize = 1024 * 1024;

// The parsed request line and the headers relevant to framing.
struct RequestHead {
    std::string method;
    std::string target;
    std::size_t content_length = 0;
    bool keep_alive = false;
    bool chunked = false;
};

struct Request {
    std::string method;
    std::string target;
    std::string body;
};

struct Response {
    int status = 200;
    std::string content_type;  // empty: no Content-Type header
    std::string body;
};

// Parses everything before the blank line ("\r\n\r\n" excluded). Returns nullopt on malformed input.
[[nodiscard]] std::optional<RequestHead> parse_head(std::string_view head);

// Serializes a response, including framing headers.
[[nodiscard]] std::string serialize(const Response& response, bool keep_alive);

}  // namespace kvhttp
