#include <arpa/inet.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <sys/socket.h>
#include <unistd.h>

#include <cerrno>
#include <chrono>
#include <cstdint>
#include <cstdlib>
#include <charconv>
#include <csignal>
#include <cstdio>
#include <cstring>
#include <exception>
#include <string_view>
#include <system_error>
#include <thread>
#include <utility>

#include "http.hpp"
#include "router.hpp"
#include "store.hpp"

namespace {

// RAII owner of a file descriptor.
class UniqueFd {
public:
    explicit UniqueFd(int fd = -1) noexcept : fd_(fd) {}
    UniqueFd(UniqueFd&& other) noexcept : fd_(std::exchange(other.fd_, -1)) {}
    UniqueFd& operator=(UniqueFd&& other) noexcept {
        if (this != &other) {
            reset();
            fd_ = std::exchange(other.fd_, -1);
        }
        return *this;
    }
    UniqueFd(const UniqueFd&) = delete;
    UniqueFd& operator=(const UniqueFd&) = delete;
    ~UniqueFd() { reset(); }

    [[nodiscard]] int get() const noexcept { return fd_; }
    void reset() noexcept {
        if (fd_ >= 0) ::close(fd_);
        fd_ = -1;
    }

private:
    int fd_;
};

[[noreturn]] void die(const char* what) {
    std::fprintf(stderr, "kvhttp: %s: %s\n", what, std::strerror(errno));
    std::exit(1);
}

UniqueFd listen_on(std::uint16_t port) {
    UniqueFd fd(::socket(AF_INET, SOCK_STREAM, 0));
    if (fd.get() < 0) die("socket");

    int one = 1;
    ::setsockopt(fd.get(), SOL_SOCKET, SO_REUSEADDR, &one, sizeof one);

    sockaddr_in addr{};
    addr.sin_family = AF_INET;
    addr.sin_port = htons(port);
    addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    if (::bind(fd.get(), reinterpret_cast<sockaddr*>(&addr), sizeof addr) < 0) die("bind");
    if (::listen(fd.get(), SOMAXCONN) < 0) die("listen");
    return fd;
}

void configure_client(int fd) {
    int one = 1;
    ::setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof one);
    ::setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &one, sizeof one);
    timeval timeout{.tv_sec = 30, .tv_usec = 0};
    ::setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof timeout);
    ::setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof timeout);
}

void drain(int fd) {
    timeval timeout{.tv_sec = 2, .tv_usec = 0};
    ::setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof timeout);
    constexpr std::size_t kMaxDrainBytes = 64 * 1024 * 1024;
    char sink[16 * 1024];
    std::size_t total = 0;
    while (total < kMaxDrainBytes) {
        ssize_t n = ::recv(fd, sink, sizeof sink, 0);
        if (n > 0) {
            total += static_cast<std::size_t>(n);
        } else if (n < 0 && errno == EINTR) {
            continue;
        } else {
            break;
        }
    }
}

void serve_connection(UniqueFd client, kvhttp::Router& router) {
    configure_client(client.get());
    kvhttp::Response response;
    try {
        auto request = kvhttp::read_request(client.get());
        if (!request) return;
        response = router.handle(*request);
    } catch (const kvhttp::HttpError& e) {
        response = kvhttp::Response{.status = e.status};
    } catch (const std::exception& e) {
        std::fprintf(stderr, "kvhttp: request failed: %s\n", e.what());
        response = kvhttp::Response{.status = 500};
    }
    if (!kvhttp::write_response(client.get(), response)) return;
    // Send FIN, then discard any unread request bytes (e.g. an oversized body we
    // rejected) so closing does not trigger a RST that could clobber the reply.
    ::shutdown(client.get(), SHUT_WR);
    drain(client.get());
}

std::uint16_t parse_port(std::string_view arg) {
    unsigned value = 0;
    auto [ptr, ec] = std::from_chars(arg.data(), arg.data() + arg.size(), value);
    if (ec != std::errc{} || ptr != arg.data() + arg.size() || value == 0 || value > 65535) {
        std::fprintf(stderr, "kvhttp: invalid port '%.*s'\n", static_cast<int>(arg.size()),
                     arg.data());
        std::exit(2);
    }
    return static_cast<std::uint16_t>(value);
}

}  // namespace

int main(int argc, char** argv) {
    if (argc != 2) {
        std::fprintf(stderr, "usage: %s <port>\n", argv[0]);
        return 2;
    }
    std::signal(SIGPIPE, SIG_IGN);

    const auto port = parse_port(argv[1]);
    UniqueFd listener = listen_on(port);

    kvhttp::Store store;
    kvhttp::Router router(store);

    for (;;) {
        int fd = ::accept(listener.get(), nullptr, nullptr);
        if (fd < 0) {
            if (errno == EINTR || errno == ECONNABORTED) continue;
            if (errno == EMFILE || errno == ENFILE) {
                std::this_thread::sleep_for(std::chrono::milliseconds(10));
                continue;
            }
            die("accept");
        }
        try {
            std::thread(serve_connection, UniqueFd(fd), std::ref(router)).detach();
        } catch (const std::system_error& e) {
            // Could not spawn a worker; drop this connection and keep serving.
            std::fprintf(stderr, "kvhttp: thread spawn failed: %s\n", e.what());
        }
    }
}
