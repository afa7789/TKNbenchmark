#pragma once

#include <cstddef>
#include <optional>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace kvhttp {

struct Request {
    std::string method;
    std::string target;
    std::vector<std::pair<std::string, std::string>> headers;
    std::string body;

    // Case-insensitive header lookup; returns the first match.
    [[nodiscard]] std::optional<std::string_view> header(std::string_view name) const;
};

struct Response {
    int status = 200;
    std::string content_type;
    std::string body;
};

// Thrown while reading a request when it cannot be served; carries the status
// code to reply with.
struct HttpError {
    int status;
};

inline constexpr std::size_t kMaxHeaderBytes = 64 * 1024;
inline constexpr std::size_t kMaxBodyBytes = 1024 * 1024;

// Reads one request from a connected socket. Returns nullopt if the peer closed
// the connection before sending anything. Throws HttpError on malformed input.
std::optional<Request> read_request(int fd);

// Serialises and sends a response, always with Content-Length and
// Connection: close. Returns false if the write failed.
bool write_response(int fd, const Response& response);

std::string_view reason_phrase(int status);

}  // namespace kvhttp
