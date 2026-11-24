#include "server.hpp"

#include <arpa/inet.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <unistd.h>

#include <cerrno>
#include <charconv>
#include <csignal>
#include <cstring>
#include <exception>
#include <iostream>
#include <optional>
#include <string>
#include <string_view>
#include <system_error>
#include <thread>
#include <utility>

namespace kvhttp {

namespace {

[[noreturn]] void throw_errno(const char* what) {
    throw std::system_error(errno, std::generic_category(), what);
}

// Owns a socket descriptor.
class Socket {
public:
    explicit Socket(int fd) noexcept : fd_(fd) {}
    ~Socket() {
        if (fd_ >= 0) {
            ::close(fd_);
        }
    }
    Socket(const Socket&) = delete;
    Socket& operator=(const Socket&) = delete;

    int fd() const noexcept { return fd_; }

private:
    int fd_;
};

// Thrown when the peer misbehaves in a way that should produce an HTTP error.
struct HttpError {
    int status;
};

// Thrown when the connection is unusable (peer closed, timeout, I/O error).
struct ConnectionClosed {};

class Connection {
public:
    Connection(int fd, const ServerOptions& options) : fd_(fd), options_(options) {}

    http::Request read_request() {
        std::optional<http::ParsedHead> head;
        while (!(head = try_parse_head())) {
            if (buffer_.size() > options_.max_head_bytes) {
                throw HttpError{431};
            }
            if (!fill()) {
                throw ConnectionClosed{};
            }
        }
        http::Request request = std::move(head->request);
        buffer_.erase(0, head->head_size);
        request.body = read_body(request);
        return request;
    }

    void send_all(std::string_view data) {
        while (!data.empty()) {
            const ssize_t n = ::send(fd_, data.data(), data.size(), 0);
            if (n < 0) {
                if (errno == EINTR) {
                    continue;
                }
                throw ConnectionClosed{};
            }
            data.remove_prefix(static_cast<std::size_t>(n));
        }
    }

    void send_response(const http::Response& response, bool include_body) {
        send_all(response.serialize_head());
        if (include_body) {
            send_all(response.body);
        }
    }

    // Half-closes the socket and discards any remaining input so the client
    // sees the response rather than a reset.
    void linger_close() {
        ::shutdown(fd_, SHUT_WR);
        timeval tv{};
        tv.tv_sec = 1;
        ::setsockopt(fd_, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof tv);
        constexpr std::size_t kMaxDrain = 16 * 1024 * 1024;
        std::size_t drained = 0;
        char scratch[16 * 1024];
        while (drained < kMaxDrain) {
            const ssize_t n = ::recv(fd_, scratch, sizeof scratch, 0);
            if (n < 0 && errno == EINTR) {
                continue;
            }
            if (n <= 0) {
                break;
            }
            drained += static_cast<std::size_t>(n);
        }
    }

private:
    std::optional<http::ParsedHead> try_parse_head() {
        const auto end = buffer_.find("\r\n\r\n");
        if (end == std::string::npos) {
            return std::nullopt;
        }
        auto parsed = http::parse_head(buffer_);
        if (!parsed) {
            throw HttpError{400};
        }
        return parsed;
    }

    // Reads more bytes into the buffer; returns false on EOF.
    bool fill() {
        char chunk[64 * 1024];
        for (;;) {
            const ssize_t n = ::recv(fd_, chunk, sizeof chunk, 0);
            if (n > 0) {
                buffer_.append(chunk, static_cast<std::size_t>(n));
                return true;
            }
            if (n == 0) {
                return false;
            }
            if (errno == EINTR) {
                continue;
            }
            if (errno == EAGAIN || errno == EWOULDBLOCK) {
                throw HttpError{408};
            }
            throw ConnectionClosed{};
        }
    }

    // Ensures at least `n` bytes are buffered.
    void require(std::size_t n) {
        while (buffer_.size() < n) {
            if (!fill()) {
                throw HttpError{400};
            }
        }
    }

    std::string take(std::size_t n) {
        require(n);
        std::string out = buffer_.substr(0, n);
        buffer_.erase(0, n);
        return out;
    }

    std::string read_line() {
        std::size_t pos;
        while ((pos = buffer_.find("\r\n")) == std::string::npos) {
            if (buffer_.size() > options_.max_head_bytes) {
                throw HttpError{400};
            }
            if (!fill()) {
                throw HttpError{400};
            }
        }
        std::string line = buffer_.substr(0, pos);
        buffer_.erase(0, pos + 2);
        return line;
    }

    std::string read_body(const http::Request& request) {
        if (auto te = request.header("Transfer-Encoding")) {
            if (!http::iequals(*te, "chunked")) {
                throw HttpError{501};
            }
            return read_chunked_body();
        }
        const auto length_header = request.header("Content-Length");
        if (!length_header) {
            return {};
        }
        std::size_t length = 0;
        const auto* first = length_header->data();
        const auto* last = first + length_header->size();
        const auto [ptr, ec] = std::from_chars(first, last, length);
        if (ec == std::errc::result_out_of_range) {
            throw HttpError{413};
        }
        if (ec != std::errc{} || ptr != last || length_header->empty()) {
            throw HttpError{400};
        }
        if (length > options_.max_body_bytes) {
            throw HttpError{413};
        }
        return take(length);
    }

    std::string read_chunked_body() {
        std::string body;
        for (;;) {
            std::string line = read_line();
            std::string_view size_text(line);
            if (auto semi = size_text.find(';'); semi != std::string_view::npos) {
                size_text = size_text.substr(0, semi);
            }
            std::size_t size = 0;
            const auto [ptr, ec] =
                std::from_chars(size_text.data(), size_text.data() + size_text.size(), size, 16);
            if (ec != std::errc{} || ptr != size_text.data() + size_text.size()) {
                throw HttpError{400};
            }
            if (size == 0) {
                // Discard trailer fields up to the terminating blank line.
                while (!read_line().empty()) {
                }
                return body;
            }
            if (size > options_.max_body_bytes - body.size()) {
                throw HttpError{413};
            }
            body += take(size);
            if (!read_line().empty()) {
                throw HttpError{400};
            }
        }
    }

    int fd_;
    const ServerOptions& options_;
    std::string buffer_;
};

void set_timeouts(int fd, std::chrono::seconds timeout) {
    timeval tv{};
    tv.tv_sec = static_cast<decltype(tv.tv_sec)>(timeout.count());
    ::setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof tv);
    ::setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof tv);
    int one = 1;
    ::setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof one);
    ::setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &one, sizeof one);
}

}  // namespace

Server::Server(ServerOptions options, Handler handler)
    : options_(std::move(options)), handler_(std::move(handler)) {
    std::signal(SIGPIPE, SIG_IGN);
}

Server::~Server() {
    if (listen_fd_ >= 0) {
        ::close(listen_fd_);
    }
}

void Server::listen() {
    listen_fd_ = ::socket(AF_INET, SOCK_STREAM, 0);
    if (listen_fd_ < 0) {
        throw_errno("socket");
    }
    int one = 1;
    ::setsockopt(listen_fd_, SOL_SOCKET, SO_REUSEADDR, &one, sizeof one);

    sockaddr_in addr{};
    addr.sin_family = AF_INET;
    addr.sin_port = htons(options_.port);
    addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    if (::bind(listen_fd_, reinterpret_cast<const sockaddr*>(&addr), sizeof addr) < 0) {
        throw_errno("bind");
    }
    if (::listen(listen_fd_, SOMAXCONN) < 0) {
        throw_errno("listen");
    }
}

void Server::run() {
    for (;;) {
        const int fd = ::accept(listen_fd_, nullptr, nullptr);
        if (fd < 0) {
            if (errno != EINTR && errno != ECONNABORTED) {
                std::cerr << "accept: " << std::strerror(errno) << '\n';
                if (errno == EMFILE || errno == ENFILE) {
                    std::this_thread::sleep_for(std::chrono::milliseconds(10));
                }
            }
            continue;
        }
        try {
            std::thread([this, fd] { handle_connection(fd); }).detach();
        } catch (const std::system_error& e) {
            std::cerr << "failed to spawn connection thread: " << e.what() << '\n';
            ::close(fd);
        }
    }
}

void Server::handle_connection(int raw_fd) const {
    Socket socket(raw_fd);
    set_timeouts(socket.fd(), options_.io_timeout);
    Connection conn(socket.fd(), options_);

    try {
        http::Request request;
        try {
            request = conn.read_request();
        } catch (const HttpError& error) {
            auto response = http::Response::text(error.status, std::string(http::reason_phrase(error.status)));
            conn.send_response(response, true);
            conn.linger_close();
            return;
        }

        http::Response response;
        try {
            response = handler_(request);
        } catch (const std::exception& e) {
            std::cerr << "handler error: " << e.what() << '\n';
            response = http::Response::text(500, "Internal Server Error");
        }
        conn.send_response(response, request.method != "HEAD");
        conn.linger_close();
    } catch (const ConnectionClosed&) {
        // Peer went away; nothing more to do.
    }
}

}  // namespace kvhttp
