#pragma once

#include <chrono>
#include <condition_variable>
#include <cstddef>
#include <cstdint>
#include <deque>
#include <mutex>
#include <stop_token>
#include <thread>
#include <vector>

#include "kvhttp/http.hpp"
#include "kvhttp/router.hpp"
#include "kvhttp/socket.hpp"

namespace kvhttp {

struct ServerOptions {
    std::uint16_t port = 8080;
    std::size_t workers = 128;
    int backlog = 1024;
    std::chrono::seconds io_timeout{30};
    Limits limits{};
};

// Blocking HTTP/1.1 server: one acceptor thread feeding a fixed pool of workers,
// each serving one request per connection.
class Server {
public:
    Server(ServerOptions options, Router router);
    Server(const Server&) = delete;
    Server& operator=(const Server&) = delete;
    ~Server();

    // Accepts connections until the process is terminated.
    [[noreturn]] void run();

private:
    void worker_loop(std::stop_token stop);
    void serve(UniqueFd conn) const;

    ServerOptions options_;
    Router router_;
    UniqueFd listener_;

    std::mutex mutex_;
    std::condition_variable_any ready_;
    std::deque<UniqueFd> pending_;
    std::vector<std::jthread> workers_;  // declared last: joined before the queue is destroyed
};

}  // namespace kvhttp
