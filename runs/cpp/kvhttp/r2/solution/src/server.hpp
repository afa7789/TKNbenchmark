#pragma once

#include <chrono>
#include <cstddef>
#include <cstdint>
#include <functional>

#include "http.hpp"

namespace kvhttp {

struct ServerOptions {
    std::uint16_t port = 8080;
    std::size_t max_head_bytes = 64 * 1024;
    std::size_t max_body_bytes = 1024 * 1024;
    std::chrono::seconds io_timeout{10};
};

using Handler = std::function<http::Response(const http::Request&)>;

// Minimal HTTP/1.1 server: one request per connection, one thread per
// connection. Listens on 127.0.0.1.
class Server {
public:
    Server(ServerOptions options, Handler handler);
    ~Server();

    Server(const Server&) = delete;
    Server& operator=(const Server&) = delete;

    // Binds and listens; throws std::system_error on failure.
    void listen();

    // Accept loop; does not return under normal operation.
    [[noreturn]] void run();

private:
    void handle_connection(int fd) const;

    ServerOptions options_;
    Handler handler_;
    int listen_fd_ = -1;
};

}  // namespace kvhttp
