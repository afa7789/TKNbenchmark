#include <arpa/inet.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <sys/socket.h>
#include <unistd.h>

#include <cerrno>
#include <chrono>
#include <cstdint>
#include <optional>
#include <utility>
#include <charconv>
#include <csignal>
#include <cstdio>
#include <cstring>
#include <exception>
#include <string_view>
#include <system_error>
#include <thread>

#include "http.hpp"
#include "kv_store.hpp"
#include "router.hpp"

namespace {

using namespace kvhttp;

// Owns a file descriptor and closes it on destruction.
class UniqueFd {
public:
    explicit UniqueFd(int fd = -1) noexcept : fd_(fd) {}
    UniqueFd(UniqueFd&& other) noexcept : fd_(std::exchange(other.fd_, -1)) {}
    UniqueFd& operator=(UniqueFd&& other) noexcept {
        if (this != &other) reset(std::exchange(other.fd_, -1));
        return *this;
    }
    UniqueFd(const UniqueFd&) = delete;
    UniqueFd& operator=(const UniqueFd&) = delete;
    ~UniqueFd() { reset(); }

    [[nodiscard]] int get() const noexcept { return fd_; }
    void reset(int fd = -1) noexcept {
        if (fd_ >= 0) ::close(fd_);
        fd_ = fd;
    }

private:
    int fd_;
};

[[noreturn]] void throw_errno(const char* what) {
    throw std::system_error(errno, std::generic_category(), what);
}

UniqueFd listen_on(std::uint16_t port) {
    UniqueFd fd(::socket(AF_INET, SOCK_STREAM, 0));
    if (fd.get() < 0) throw_errno("socket");

    const int one = 1;
    ::setsockopt(fd.get(), SOL_SOCKET, SO_REUSEADDR, &one, sizeof one);

    sockaddr_in addr{};
    addr.sin_family = AF_INET;
    addr.sin_port = htons(port);
    addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    if (::bind(fd.get(), reinterpret_cast<const sockaddr*>(&addr), sizeof addr) < 0)
        throw_errno("bind");
    if (::listen(fd.get(), SOMAXCONN) < 0) throw_errno("listen");
    return fd;
}

void configure_client(int fd) {
    const int one = 1;
#ifdef SO_NOSIGPIPE
    ::setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof one);
#endif
    ::setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &one, sizeof one);
    // Don't let an idle or stalled client pin a thread forever.
    timeval timeout{.tv_sec = 30, .tv_usec = 0};
    ::setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof timeout);
    ::setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof timeout);
}

void serve_connection(UniqueFd client, const Router& router) {
    configure_client(client.get());
    static const Limits limits{};

    auto [request, error] = read_request(client.get(), limits);
    if (request) {
        Response response;
        try {
            response = router.handle(*request);
        } catch (const std::exception&) {
            response = Response::empty(500);
        }
        write_response(client.get(), response);
    } else if (error) {
        write_response(client.get(), *error);
    }
    // Half-close so the client reads the full response before the FIN.
    ::shutdown(client.get(), SHUT_WR);
}

std::optional<std::uint16_t> parse_port(std::string_view s) {
    unsigned value = 0;
    const auto [ptr, ec] = std::from_chars(s.data(), s.data() + s.size(), value);
    if (ec != std::errc{} || ptr != s.data() + s.size() || value == 0 || value > 65535)
        return std::nullopt;
    return static_cast<std::uint16_t>(value);
}

}  // namespace

int main(int argc, char** argv) {
    if (argc != 2) {
        std::fprintf(stderr, "usage: %s <port>\n", argv[0]);
        return 2;
    }
    const auto port = parse_port(argv[1]);
    if (!port) {
        std::fprintf(stderr, "invalid port: %s\n", argv[1]);
        return 2;
    }

    std::signal(SIGPIPE, SIG_IGN);

    try {
        UniqueFd listener = listen_on(*port);
        KvStore store;
        const Router router(store);

        for (;;) {
            const int fd = ::accept(listener.get(), nullptr, nullptr);
            if (fd < 0) {
                if (errno == EINTR || errno == ECONNABORTED) continue;
                if (errno == EMFILE || errno == ENFILE) {
                    std::this_thread::sleep_for(std::chrono::milliseconds(10));
                    continue;
                }
                throw_errno("accept");
            }
            // One thread per connection: connections are short-lived and the
            // required concurrency is modest.
            try {
                std::thread(serve_connection, UniqueFd(fd), std::cref(router)).detach();
            } catch (const std::system_error& e) {
                std::fprintf(stderr, "failed to spawn handler: %s\n", e.what());
            }
        }
    } catch (const std::exception& e) {
        std::fprintf(stderr, "fatal: %s\n", e.what());
        return 1;
    }
}
