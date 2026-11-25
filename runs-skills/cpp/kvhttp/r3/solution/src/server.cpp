#include "kvhttp/server.hpp"

#include <sys/socket.h>

#include <array>
#include <cerrno>
#include <exception>
#include <iostream>
#include <string>
#include <string_view>
#include <system_error>
#include <utility>

namespace kvhttp {
namespace {

// How long to keep reading after an error response so the client sees the
// response instead of a connection reset.
constexpr std::chrono::milliseconds drain_timeout{2000};
constexpr std::size_t drain_limit = 64 * 1024 * 1024;

bool write_response(int fd, const Response& res) {
    const std::string head = serialize_head(res);
    const std::array<std::string_view, 2> parts{head, res.body};
    return send_all(fd, parts);
}

}  // namespace

Server::Server(ServerOptions options, Router router)
    : options_(options), router_(router), listener_(listen_tcp(options.port, options.backlog)) {
    workers_.reserve(options_.workers);
    for (std::size_t i = 0; i < options_.workers; ++i) {
        workers_.emplace_back([this](std::stop_token stop) { worker_loop(std::move(stop)); });
    }
}

Server::~Server() {
    for (auto& w : workers_) w.request_stop();
    ready_.notify_all();
}

void Server::run() {
    for (;;) {
        UniqueFd conn{::accept(listener_.get(), nullptr, nullptr)};
        if (!conn) {
            if (errno == EINTR || errno == ECONNABORTED) continue;
            // Typically EMFILE/ENFILE: back off briefly instead of spinning.
            std::cerr << "accept: " << std::system_category().message(errno) << '\n';
            std::this_thread::sleep_for(std::chrono::milliseconds(10));
            continue;
        }
        configure_connection(conn.get(), options_.io_timeout);
        {
            std::scoped_lock lock(mutex_);
            pending_.push_back(std::move(conn));
        }
        ready_.notify_one();
    }
}

void Server::worker_loop(std::stop_token stop) {
    for (;;) {
        UniqueFd conn;
        {
            std::unique_lock lock(mutex_);
            if (!ready_.wait(lock, stop, [this] { return !pending_.empty(); })) return;
            conn = std::move(pending_.front());
            pending_.pop_front();
        }
        try {
            serve(std::move(conn));
        } catch (const std::exception& e) {
            std::cerr << "connection error: " << e.what() << '\n';
        }
    }
}

void Server::serve(UniqueFd conn) const {
    const int fd = conn.get();
    RequestReader reader(fd, options_.limits);

    Response res;
    bool request_complete = false;
    try {
        auto req = reader.read();
        if (!req) return;  // peer went away before sending a full request
        request_complete = true;
        res = router_.handle(std::move(*req));
    } catch (const HttpError& e) {
        res = Response::text(e.status(), e.what());
    } catch (const std::bad_alloc&) {
        res = Response::text(500, "out of memory");
    }

    if (!write_response(fd, res)) return;
    ::shutdown(fd, SHUT_WR);
    if (!request_complete) {
        // Unread input would make close() send a RST that can destroy the
        // response before the client reads it.
        set_receive_timeout(fd, drain_timeout);
        drain(fd, drain_limit);
    }
}

}  // namespace kvhttp
