#pragma once

#include "router.hpp"

#include <condition_variable>
#include <cstdint>
#include <deque>
#include <mutex>
#include <stop_token>
#include <thread>
#include <utility>
#include <vector>

namespace kvhttp {

// Owns a file descriptor and closes it on destruction.
class UniqueFd {
public:
    UniqueFd() noexcept = default;
    explicit UniqueFd(int fd) noexcept : fd_(fd) {}
    UniqueFd(UniqueFd&& other) noexcept : fd_(std::exchange(other.fd_, -1)) {}
    UniqueFd& operator=(UniqueFd&& other) noexcept {
        if (this != &other) reset(std::exchange(other.fd_, -1));
        return *this;
    }
    UniqueFd(const UniqueFd&) = delete;
    UniqueFd& operator=(const UniqueFd&) = delete;
    ~UniqueFd() { reset(); }

    [[nodiscard]] int get() const noexcept { return fd_; }
    [[nodiscard]] explicit operator bool() const noexcept { return fd_ >= 0; }
    void reset(int fd = -1) noexcept;

private:
    int fd_ = -1;
};

struct ServerOptions {
    std::uint16_t port = 0;
    std::size_t worker_count = 128;
    int idle_timeout_seconds = 10;
};

// Blocking HTTP/1.1 server: one accept loop feeding a fixed pool of connection workers.
class Server {
public:
    Server(ServerOptions options, const Router& router);

    // Accepts connections forever (until the process is terminated).
    [[noreturn]] void run();

private:
    void worker_loop(std::stop_token stop);
    void serve_connection(const UniqueFd& client) const;

    ServerOptions options_;
    const Router& router_;
    UniqueFd listener_;

    std::mutex mutex_;
    std::condition_variable_any ready_;
    std::deque<UniqueFd> pending_;
    std::vector<std::jthread> workers_;  // last member: joined before the rest is destroyed
};

}  // namespace kvhttp
