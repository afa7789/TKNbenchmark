#pragma once

#include <cstddef>
#include <optional>
#include <stdexcept>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace kvhttp {

struct Header {
    std::string name;
    std::string value;
};

struct Request {
    std::string method;
    std::string path;  // request target without any query string
    std::vector<Header> headers;
    std::string body;

    // Case-insensitive header lookup; returns the first match.
    [[nodiscard]] std::optional<std::string_view> header(std::string_view name) const;
};

struct Response {
    int status = 200;
    std::vector<Header> headers;
    std::string body;

    [[nodiscard]] static Response empty(int status) { return Response{.status = status, .headers = {}, .body = {}}; }
    [[nodiscard]] static Response text(int status, std::string body);
    [[nodiscard]] static Response json(int status, std::string body);
    [[nodiscard]] static Response binary(int status, std::string body);
};

// A request that cannot be served; carries the status code to reply with.
class HttpError : public std::runtime_error {
public:
    HttpError(int status, const std::string& what) : std::runtime_error(what), status_(status) {}
    [[nodiscard]] int status() const noexcept { return status_; }

private:
    int status_;
};

struct Limits {
    std::size_t max_line = 8 * 1024;
    std::size_t max_headers = 100;
    std::size_t max_body = 1024 * 1024;
};

// Reads HTTP/1.x requests from a connected socket.
class RequestReader {
public:
    RequestReader(int fd, Limits limits) : fd_(fd), limits_(limits) {}

    // Returns nullopt if the peer closed the connection (or timed out) before a
    // complete request arrived. Throws HttpError for malformed or oversized requests.
    [[nodiscard]] std::optional<Request> read();

private:
    struct PeerClosed {};

    bool fill();
    std::string read_line();
    void read_exact(std::size_t n, std::string& out);
    void read_head(Request& req);
    void read_body(Request& req);
    void read_chunked_body(std::string& out);
    void send_continue_if_expected(const Request& req);

    int fd_;
    Limits limits_;
    std::string buf_;
    std::size_t pos_ = 0;
};

[[nodiscard]] std::string_view reason_phrase(int status) noexcept;

// Serializes the status line and headers, including Content-Length and Connection: close.
[[nodiscard]] std::string serialize_head(const Response& res);

}  // namespace kvhttp
