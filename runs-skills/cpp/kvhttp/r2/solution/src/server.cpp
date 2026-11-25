#include "server.hpp"

#include <arpa/inet.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <sys/socket.h>
#include <sys/time.h>

#include <array>
#include <cerrno>
#include <cstring>
#include <exception>
#include <iostream>
#include <optional>
#include <string>
#include <string_view>
#include <system_error>
#include <variant>

namespace kvhttp {
namespace {

constexpr std::string_view kHeadTerminator = "\r\n\r\n";
constexpr int kIoTimeoutSeconds = 10;
constexpr std::size_t kReadChunk = 64 * 1024;

[[noreturn]] void throw_errno(const char* what) { throw std::system_error(errno, std::generic_category(), what); }

template <typename T>
void set_option(int fd, int level, int name, const T& value) noexcept {
  // Best effort: a failure here only degrades timeouts or latency.
  (void)::setsockopt(fd, level, name, &value, sizeof(value));
}

void set_timeouts(int fd, int seconds) noexcept {
  const timeval tv{.tv_sec = seconds, .tv_usec = 0};
  set_option(fd, SOL_SOCKET, SO_RCVTIMEO, tv);
  set_option(fd, SOL_SOCKET, SO_SNDTIMEO, tv);
}

bool send_all(int fd, std::string_view data) noexcept {
  while (!data.empty()) {
    const ssize_t n = ::send(fd, data.data(), data.size(), 0);
    if (n < 0) {
      if (errno == EINTR) continue;
      return false;
    }
    data.remove_prefix(static_cast<std::size_t>(n));
  }
  return true;
}

enum class ReadResult { ok, eof, error };

// Appends up to kReadChunk bytes from the socket to `buffer`.
ReadResult read_some(int fd, std::string& buffer) {
  std::array<char, kReadChunk> chunk;
  for (;;) {
    const ssize_t n = ::recv(fd, chunk.data(), chunk.size(), 0);
    if (n > 0) {
      buffer.append(chunk.data(), static_cast<std::size_t>(n));
      return ReadResult::ok;
    }
    if (n == 0) return ReadResult::eof;
    if (errno != EINTR) return ReadResult::error;
  }
}

// Reads one complete request, or the error to answer with instead.
// std::monostate means the peer went away and no reply is possible.
std::variant<Request, HttpError, std::monostate> read_request(int fd) {
  std::string buffer;
  std::size_t head_end = std::string::npos;
  while ((head_end = buffer.find(kHeadTerminator)) == std::string::npos) {
    if (buffer.size() > kMaxHeaderBytes) return HttpError{431, "request head too large"};
    switch (read_some(fd, buffer)) {
      case ReadResult::ok: break;
      case ReadResult::eof:
        if (buffer.empty()) return std::monostate{};
        return HttpError{400, "incomplete request head"};
      case ReadResult::error:
        if (errno == EAGAIN || errno == EWOULDBLOCK) return HttpError{408, "request timeout"};
        return std::monostate{};
    }
  }
  if (head_end > kMaxHeaderBytes) return HttpError{431, "request head too large"};

  auto parsed = parse_request_head(std::string_view(buffer).substr(0, head_end));
  if (auto* error = std::get_if<HttpError>(&parsed)) return std::move(*error);
  Request request{.head = std::move(std::get<RequestHead>(parsed)), .body = {}};

  const auto length = body_length(request.head);
  if (const auto* error = std::get_if<HttpError>(&length)) return *error;
  const std::size_t content_length = std::get<std::size_t>(length);

  request.body = buffer.substr(head_end + kHeadTerminator.size());
  if (request.body.size() < content_length) {
    const auto expect = request.head.header("Expect");
    if (expect && *expect == "100-continue" && !send_all(fd, "HTTP/1.1 100 Continue\r\n\r\n")) return std::monostate{};
    request.body.reserve(content_length);
  }
  while (request.body.size() < content_length) {
    switch (read_some(fd, request.body)) {
      case ReadResult::ok: break;
      case ReadResult::eof: return std::monostate{};
      case ReadResult::error:
        if (errno == EAGAIN || errno == EWOULDBLOCK) return HttpError{408, "request timeout"};
        return std::monostate{};
    }
  }
  // Ignore anything beyond the declared length: one request per connection.
  request.body.resize(content_length);
  return request;
}

// Half-closes the connection and briefly drains unread input, so the peer
// receives the full response instead of a reset.
void finish(int fd) noexcept {
  ::shutdown(fd, SHUT_WR);
  set_timeouts(fd, 1);
  std::array<char, 4096> sink;
  std::size_t drained = 0;
  while (drained < kMaxBodyBytes) {
    const ssize_t n = ::recv(fd, sink.data(), sink.size(), 0);
    if (n <= 0) break;
    drained += static_cast<std::size_t>(n);
  }
}

}  // namespace

Server::Server(ServerOptions options, const Router& router) : options_(options), router_(router) {}

void Server::listen() {
  Socket fd(::socket(AF_INET, SOCK_STREAM, 0));
  if (!fd.valid()) throw_errno("socket");
  set_option(fd.get(), SOL_SOCKET, SO_REUSEADDR, 1);

  sockaddr_in addr{};
  addr.sin_family = AF_INET;
  addr.sin_port = htons(options_.port);
  addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
  if (::bind(fd.get(), reinterpret_cast<const sockaddr*>(&addr), sizeof(addr)) < 0) throw_errno("bind");
  if (::listen(fd.get(), SOMAXCONN) < 0) throw_errno("listen");
  listener_ = std::move(fd);

  workers_.reserve(options_.worker_threads);
  for (std::size_t i = 0; i < options_.worker_threads; ++i) {
    workers_.emplace_back([this](std::stop_token stop) { worker_loop(stop); });
  }
}

void Server::run() {
  for (;;) {
    Socket client(::accept(listener_.get(), nullptr, nullptr));
    if (!client.valid()) {
      if (errno != EINTR && errno != ECONNABORTED) std::cerr << "accept: " << std::strerror(errno) << '\n';
      continue;
    }
    {
      std::scoped_lock lock(queue_mutex_);
      queue_.push_back(std::move(client));
    }
    queue_cv_.notify_one();
  }
}

void Server::worker_loop(std::stop_token stop) {
  for (;;) {
    Socket client;
    {
      std::unique_lock lock(queue_mutex_);
      if (!queue_cv_.wait(lock, stop, [this] { return !queue_.empty(); })) return;
      client = std::move(queue_.front());
      queue_.pop_front();
    }
    serve(std::move(client));
  }
}

void Server::serve(Socket client) const {
  const int fd = client.get();
  set_timeouts(fd, kIoTimeoutSeconds);
  set_option(fd, SOL_SOCKET, SO_NOSIGPIPE, 1);
  set_option(fd, IPPROTO_TCP, TCP_NODELAY, 1);

  Response response;
  try {
    auto request = read_request(fd);
    if (std::holds_alternative<std::monostate>(request)) return;
    if (auto* error = std::get_if<HttpError>(&request)) {
      response = Response::text(error->status, std::move(error->message));
    } else {
      response = router_.handle(std::move(std::get<Request>(request)));
    }
  } catch (const std::exception& e) {
    std::cerr << "request failed: " << e.what() << '\n';
    response = Response::text(500, "internal error");
  }

  if (send_all(fd, serialize(response))) finish(fd);
}

}  // namespace kvhttp
