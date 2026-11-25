#pragma once

#include <chrono>
#include <cstddef>
#include <cstdint>
#include <span>
#include <string>
#include <string_view>

namespace kvhttp {

// Owning wrapper around a POSIX file descriptor.
class UniqueFd {
public:
    UniqueFd() noexcept = default;
    explicit UniqueFd(int fd) noexcept : fd_(fd) {}
    UniqueFd(UniqueFd&& other) noexcept : fd_(other.release()) {}
    UniqueFd& operator=(UniqueFd&& other) noexcept;
    UniqueFd(const UniqueFd&) = delete;
    UniqueFd& operator=(const UniqueFd&) = delete;
    ~UniqueFd();

    [[nodiscard]] int get() const noexcept { return fd_; }
    [[nodiscard]] explicit operator bool() const noexcept { return fd_ >= 0; }
    int release() noexcept;
    void reset(int fd = -1) noexcept;

private:
    int fd_ = -1;
};

// Creates a listening TCP socket bound to 127.0.0.1:port. Throws std::system_error.
[[nodiscard]] UniqueFd listen_tcp(std::uint16_t port, int backlog);

// Applies per-connection options: send/receive timeouts, SIGPIPE suppression.
void configure_connection(int fd, std::chrono::seconds io_timeout);

void set_receive_timeout(int fd, std::chrono::milliseconds timeout);

// Writes every byte of every buffer, retrying on partial writes.
// Returns false if the peer went away or the write timed out.
[[nodiscard]] bool send_all(int fd, std::span<const std::string_view> buffers);

// Reads and discards input until EOF, error/timeout or `limit` bytes.
void drain(int fd, std::size_t limit);

}  // namespace kvhttp
