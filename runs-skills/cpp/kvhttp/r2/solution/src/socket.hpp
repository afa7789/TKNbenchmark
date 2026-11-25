#pragma once

#include <unistd.h>

#include <utility>

namespace kvhttp {

// Owning wrapper around a socket file descriptor.
class Socket {
 public:
  Socket() noexcept = default;
  explicit Socket(int fd) noexcept : fd_(fd) {}
  Socket(Socket&& other) noexcept : fd_(std::exchange(other.fd_, -1)) {}
  Socket& operator=(Socket&& other) noexcept {
    if (this != &other) reset(std::exchange(other.fd_, -1));
    return *this;
  }
  Socket(const Socket&) = delete;
  Socket& operator=(const Socket&) = delete;
  ~Socket() { reset(); }

  [[nodiscard]] int get() const noexcept { return fd_; }
  [[nodiscard]] bool valid() const noexcept { return fd_ >= 0; }

  void reset(int fd = -1) noexcept {
    if (fd_ >= 0) ::close(fd_);
    fd_ = fd;
  }

 private:
  int fd_ = -1;
};

}  // namespace kvhttp
