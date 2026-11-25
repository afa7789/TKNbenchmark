#include "kvhttp/socket.hpp"

#include <arpa/inet.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <sys/socket.h>
#include <sys/uio.h>
#include <unistd.h>

#include <algorithm>
#include <array>
#include <cerrno>
#include <system_error>
#include <utility>
#include <vector>

namespace kvhttp {
namespace {

[[noreturn]] void throw_errno(const char* what) {
    throw std::system_error(errno, std::generic_category(), what);
}

timeval to_timeval(std::chrono::microseconds d) {
    const auto secs = std::chrono::duration_cast<std::chrono::seconds>(d);
    timeval tv{};
    tv.tv_sec = static_cast<decltype(tv.tv_sec)>(secs.count());
    tv.tv_usec = static_cast<decltype(tv.tv_usec)>((d - secs).count());
    return tv;
}

void set_option(int fd, int level, int name, const void* value, socklen_t len) {
    // Best effort: a failure here only degrades robustness, never correctness.
    (void)::setsockopt(fd, level, name, value, len);
}

}  // namespace

UniqueFd& UniqueFd::operator=(UniqueFd&& other) noexcept {
    if (this != &other) reset(other.release());
    return *this;
}

UniqueFd::~UniqueFd() { reset(); }

int UniqueFd::release() noexcept { return std::exchange(fd_, -1); }

void UniqueFd::reset(int fd) noexcept {
    if (fd_ >= 0) ::close(fd_);
    fd_ = fd;
}

UniqueFd listen_tcp(std::uint16_t port, int backlog) {
    UniqueFd fd{::socket(AF_INET, SOCK_STREAM, 0)};
    if (!fd) throw_errno("socket");

    const int one = 1;
    set_option(fd.get(), SOL_SOCKET, SO_REUSEADDR, &one, sizeof one);

    sockaddr_in addr{};
    addr.sin_family = AF_INET;
    addr.sin_port = htons(port);
    addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    if (::bind(fd.get(), reinterpret_cast<const sockaddr*>(&addr), sizeof addr) != 0) throw_errno("bind");
    if (::listen(fd.get(), backlog) != 0) throw_errno("listen");
    return fd;
}

void set_receive_timeout(int fd, std::chrono::milliseconds timeout) {
    const timeval tv = to_timeval(timeout);
    set_option(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof tv);
}

void configure_connection(int fd, std::chrono::seconds io_timeout) {
    const timeval tv = to_timeval(io_timeout);
    set_option(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof tv);
    set_option(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof tv);
    const int one = 1;
    set_option(fd, IPPROTO_TCP, TCP_NODELAY, &one, sizeof one);
#ifdef SO_NOSIGPIPE
    set_option(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof one);
#endif
}

bool send_all(int fd, std::span<const std::string_view> buffers) {
    std::vector<iovec> iov;
    iov.reserve(buffers.size());
    for (const auto b : buffers) {
        if (!b.empty()) iov.push_back({const_cast<char*>(b.data()), b.size()});
    }

    std::size_t first = 0;
    while (first < iov.size()) {
        const auto count = static_cast<int>(std::min<std::size_t>(iov.size() - first, IOV_MAX));
        const ssize_t n = ::writev(fd, iov.data() + first, count);
        if (n < 0) {
            if (errno == EINTR) continue;
            return false;
        }
        auto written = static_cast<std::size_t>(n);
        while (first < iov.size() && written >= iov[first].iov_len) {
            written -= iov[first].iov_len;
            ++first;
        }
        if (written > 0) {
            iov[first].iov_base = static_cast<char*>(iov[first].iov_base) + written;
            iov[first].iov_len -= written;
        }
    }
    return true;
}

void drain(int fd, std::size_t limit) {
    std::array<char, 16 * 1024> scratch{};
    std::size_t total = 0;
    while (total < limit) {
        const ssize_t n = ::recv(fd, scratch.data(), scratch.size(), 0);
        if (n < 0 && errno == EINTR) continue;
        if (n <= 0) return;
        total += static_cast<std::size_t>(n);
    }
}

}  // namespace kvhttp
