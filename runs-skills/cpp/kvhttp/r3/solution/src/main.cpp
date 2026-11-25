#include <csignal>
#include <cstdint>
#include <exception>
#include <iostream>
#include <optional>
#include <string_view>
#include <charconv>

#include "kvhttp/kv_store.hpp"
#include "kvhttp/router.hpp"
#include "kvhttp/server.hpp"

namespace {

std::optional<std::uint16_t> parse_port(std::string_view s) noexcept {
    std::uint16_t port{};
    const auto [end, ec] = std::from_chars(s.data(), s.data() + s.size(), port);
    if (ec != std::errc{} || end != s.data() + s.size() || port == 0) return std::nullopt;
    return port;
}

}  // namespace

int main(int argc, char* argv[]) {
    if (argc != 2) {
        std::cerr << "usage: " << argv[0] << " <port>\n";
        return 2;
    }
    const auto port = parse_port(argv[1]);
    if (!port) {
        std::cerr << "invalid port: " << argv[1] << '\n';
        return 2;
    }

    // Write errors are reported through return codes instead.
    std::signal(SIGPIPE, SIG_IGN);

    try {
        kvhttp::KvStore store;
        kvhttp::Server server(kvhttp::ServerOptions{.port = *port}, kvhttp::Router(store));
        server.run();
    } catch (const std::exception& e) {
        std::cerr << "fatal: " << e.what() << '\n';
        return 1;
    }
}
