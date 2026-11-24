#pragma once

#include <cstddef>
#include <memory>
#include <optional>
#include <string>
#include <utility>
#include <vector>

namespace kvhttp {

struct Request {
    std::string method;
    std::string target;
    std::string body;
};

struct Response {
    int status = 200;
    std::vector<std::pair<std::string, std::string>> headers;
    // Body is shared so stored values can be sent without copying.
    std::shared_ptr<const std::string> body;

    static Response make(int status, std::string body = {},
                         std::string content_type = "text/plain; charset=utf-8");
    static Response empty(int status);
};

// Limits applied while reading a request.
struct Limits {
    std::size_t max_header_bytes = 64 * 1024;
    std::size_t max_body_bytes = 1024 * 1024;
};

// Reads one request from a connected socket. On a protocol error, returns
// the error response to send instead.
struct ReadResult {
    std::optional<Request> request;
    std::optional<Response> error;  // set when the request was malformed
};

ReadResult read_request(int fd, const Limits& limits);

// Writes the full response; returns false if the peer went away.
bool write_response(int fd, const Response& response);

const char* reason_phrase(int status);

}  // namespace kvhttp
