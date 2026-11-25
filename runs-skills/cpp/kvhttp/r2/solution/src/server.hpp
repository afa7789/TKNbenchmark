#pragma once

#include <condition_variable>
#include <cstdint>
#include <deque>
#include <mutex>
#include <thread>
#include <vector>

#include "router.hpp"
#include "socket.hpp"

namespace kvhttp {

struct ServerOptions {
  std::uint16_t port = 0;
  std::size_t worker_threads = 128;
};

// Blocking HTTP/1.1 server: one acceptor thread hands connections to a fixed
// pool of workers; each connection serves a single request and is closed.
class Server {
 public:
  Server(ServerOptions options, const Router& router);

  // Binds 127.0.0.1:<port>; throws std::system_error on failure.
  void listen();
  // Accepts connections until the process is terminated.
  [[noreturn]] void run();

 private:
  void worker_loop(std::stop_token stop);
  void serve(Socket client) const;

  ServerOptions options_;
  const Router& router_;
  Socket listener_;

  std::mutex queue_mutex_;
  std::condition_variable_any queue_cv_;
  std::deque<Socket> queue_;
  std::vector<std::jthread> workers_;
};

}  // namespace kvhttp
