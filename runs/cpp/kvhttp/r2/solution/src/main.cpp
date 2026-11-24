#include <charconv>
#include <cstdint>
#include <exception>
#include <iostream>
#include <string_view>

#include "kv_store.hpp"
#include "routes.hpp"
#include "server.hpp"

int main(int argc, char** argv) {
    if (argc != 2) {
        std::cerr << "usage: " << argv[0] << " <port>\n";
        return 2;
    }
    const std::string_view port_arg = argv[1];
    std::uint16_t port = 0;
    const auto [ptr, ec] = std::from_chars(port_arg.data(), port_arg.data() + port_arg.size(), port);
    if (ec != std::errc{} || ptr != port_arg.data() + port_arg.size() || port == 0) {
        std::cerr << "invalid port: " << port_arg << '\n';
        return 2;
    }

    try {
        kvhttp::KvStore store;
        kvhttp::ServerOptions options;
        options.port = port;
        kvhttp::Server server(options, [&store](const kvhttp::http::Request& request) {
            return kvhttp::route(store, request);
        });
        server.listen();
        server.run();
    } catch (const std::exception& e) {
        std::cerr << "fatal: " << e.what() << '\n';
        return 1;
    }
}
