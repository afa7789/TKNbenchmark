#include "server.hpp"

#include <arpa/inet.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <unistd.h>

#include <algorithm>
#include <cerrno>
#include <chrono>
#include <optional>
#include <string>
#include <system_error>

namespace kvhttp {
namespace {

[[noreturn]] void throw_errno(const char* what) {
    throw std::system_error(errno, std::generic_category(), what);
}

void set_option(int fd, int level, int name, const void* value, socklen_t size) {
    if (::setsockopt(fd, level, name, value, size) != 0) throw_errno("setsockopt");
}

template <typename T>
void set_option(int fd, int level, int name, const T& value) {
    set_option(fd, level, name, &value, sizeof(value));
}

// Writes the whole buffer; returns false if the peer went away.
bool send_all(int fd, std::string_view data) noexcept {
    while (!data.empty()) {
        const auto n = ::send(fd, data.data(), data.size(), 0);
        if (n < 0) {
            if (errno == EINTR) continue;
            return false;
        }
        data.remove_prefix(static_cast<std::size_t>(n));
    }
    return true;
}

// Buffered reader over a connected socket.
class Connection {
public:
    explicit Connection(int fd) noexcept : fd_(fd) {}

    // Reads until the end of the header block. Returns the head (without the blank line),
    // or nullopt on EOF/timeout/error. Sets `too_large` if the head exceeds the limit.
    std::optional<std::string> read_head(bool& too_large) {
        too_large = false;
        std::size_t scanned = 0;
        while (true) {
            const auto pos = buffer_.find("\r\n\r\n", scanned);
            if (pos != std::string::npos) {
                std::string head = buffer_.substr(0, pos);
                buffer_.erase(0, pos + 4);
                return head;
            }
            if (buffer_.size() > kMaxHeadSize) {
                too_large = true;
                return std::nullopt;
            }
            scanned = buffer_.size() >= 3 ? buffer_.size() - 3 : 0;
            if (!fill()) return std::nullopt;
        }
    }

    // Reads exactly `size` body bytes following the head.
    std::optional<std::string> read_body(std::size_t size) {
        while (buffer_.size() < size) {
            if (!fill(size - buffer_.size())) return std::nullopt;
        }
        std::string body;
        if (buffer_.size() == size) {
            body.swap(buffer_);
        } else {
            body = buffer_.substr(0, size);
            buffer_.erase(0, size);
        }
        return body;
    }


private:
    bool fill(std::size_t hint = 0) {
        constexpr std::size_t kChunk = 64 * 1024;
        const std::size_t want = std::max(kChunk, std::min(hint, kMaxBodySize));
        const std::size_t old_size = buffer_.size();
        buffer_.resize(old_size + want);
        while (true) {
            const auto n = ::recv(fd_, buffer_.data() + old_size, want, 0);
            if (n > 0) {
                buffer_.resize(old_size + static_cast<std::size_t>(n));
                return true;
            }
            if (n < 0 && errno == EINTR) continue;
            buffer_.resize(old_size);
            return false;  // EOF, timeout (EAGAIN) or error
        }
    }

    int fd_;
    std::string buffer_;
};

}  // namespace

void UniqueFd::reset(int fd) noexcept {
    if (fd_ >= 0) ::close(fd_);
    fd_ = fd;
}

Server::Server(ServerOptions options, const Router& router)
    : options_(options), router_(router), listener_(::socket(AF_INET, SOCK_STREAM, 0)) {
    if (!listener_) throw_errno("socket");
    set_option(listener_.get(), SOL_SOCKET, SO_REUSEADDR, 1);

    sockaddr_in addr{};
    addr.sin_family = AF_INET;
    addr.sin_port = htons(options_.port);
    addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    if (::bind(listener_.get(), reinterpret_cast<const sockaddr*>(&addr), sizeof(addr)) != 0) {
        throw_errno("bind");
    }
    if (::listen(listener_.get(), SOMAXCONN) != 0) throw_errno("listen");

    workers_.reserve(options_.worker_count);
    for (std::size_t i = 0; i < options_.worker_count; ++i) {
        workers_.emplace_back([this](std::stop_token stop) { worker_loop(stop); });
    }
}

void Server::run() {
    while (true) {
        UniqueFd client(::accept(listener_.get(), nullptr, nullptr));
        if (!client) {
            // Transient failures (EINTR, ECONNABORTED, EMFILE, ...) must not stop the server.
            if (errno == EMFILE || errno == ENFILE) std::this_thread::sleep_for(std::chrono::milliseconds(10));
            continue;
        }
        {
            std::scoped_lock lock(mutex_);
            pending_.push_back(std::move(client));
        }
        ready_.notify_one();
    }
}

void Server::worker_loop(std::stop_token stop) {
    while (true) {
        UniqueFd client;
        {
            std::unique_lock lock(mutex_);
            if (!ready_.wait(lock, stop, [this] { return !pending_.empty(); })) return;
            client = std::move(pending_.front());
            pending_.pop_front();
        }
        try {
            serve_connection(client);
        } catch (const std::exception&) {
            // Drop this connection (e.g. allocation failure); keep the worker alive.
        }
    }
}

void Server::serve_connection(const UniqueFd& client) const {
    const int fd = client.get();
    const timeval timeout{.tv_sec = options_.idle_timeout_seconds, .tv_usec = 0};
    set_option(fd, SOL_SOCKET, SO_RCVTIMEO, timeout);
    set_option(fd, SOL_SOCKET, SO_SNDTIMEO, timeout);
    set_option(fd, SOL_SOCKET, SO_NOSIGPIPE, 1);
    set_option(fd, IPPROTO_TCP, TCP_NODELAY, 1);

    auto reply = [fd](int status) {
        (void)send_all(fd, serialize(Response{.status = status, .content_type = {}, .body = {}}, false));
    };

    Connection conn(fd);
    while (true) {
        bool too_large = false;
        auto head_text = conn.read_head(too_large);
        if (!head_text) {
            if (too_large) reply(431);
            return;
        }
        auto head = parse_head(*head_text);
        if (!head) return reply(400);
        if (head->chunked) return reply(501);
        if (head->content_length > kMaxBodySize) return reply(413);

        auto body = conn.read_body(head->content_length);
        if (!body) return;

        const bool keep_alive = head->keep_alive;
        Response response = router_.handle(Request{
            .method = std::move(head->method),
            .target = std::move(head->target),
            .body = std::move(*body),
        });
        if (!send_all(fd, serialize(response, keep_alive)) || !keep_alive) return;
    }
}

}  // namespace kvhttp
