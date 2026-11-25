#include "lru_cache.hpp"

#include <charconv>
#include <cstddef>
#include <cstdio>
#include <iostream>
#include <iterator>
#include <optional>
#include <string>
#include <string_view>

namespace {

std::string read_all(std::FILE* in) {
    std::string data;
    char buf[1 << 16];
    std::size_t n = 0;
    while ((n = std::fread(buf, 1, sizeof buf, in)) > 0) {
        data.append(buf, n);
    }
    return data;
}

// Splits off the next line (without its terminator) from `rest`.
std::string_view next_line(std::string_view& rest) {
    const auto pos = rest.find('\n');
    std::string_view line = rest.substr(0, pos);
    rest = pos == std::string_view::npos ? std::string_view{} : rest.substr(pos + 1);
    if (!line.empty() && line.back() == '\r') {
        line.remove_suffix(1);
    }
    return line;
}

// Splits off the next space-separated token from `rest`.
std::string_view next_token(std::string_view& rest) {
    const auto pos = rest.find(' ');
    std::string_view token = rest.substr(0, pos);
    rest = pos == std::string_view::npos ? std::string_view{} : rest.substr(pos + 1);
    return token;
}

std::optional<std::size_t> parse_size(std::string_view s) {
    std::size_t v{};
    const auto [p, ec] = std::from_chars(s.data(), s.data() + s.size(), v);
    if (ec != std::errc{} || p != s.data() + s.size()) {
        return std::nullopt;
    }
    return v;
}

void execute(LruCache& cache, std::string_view line, std::string& out) {
    const std::string_view command = next_token(line);
    if (command == "SET") {
        const std::string_view key = next_token(line);
        const std::string_view value = next_token(line);
        cache.set(key, value);
    } else if (command == "GET") {
        if (const auto value = cache.get(next_token(line))) {
            out.append(*value);
        } else {
            out.append("NULL");
        }
        out.push_back('\n');
    } else if (command == "DEL") {
        out.append(cache.erase(next_token(line)) ? "1\n" : "0\n");
    } else if (command == "SIZE") {
        out.append(std::to_string(cache.size()));
        out.push_back('\n');
    }
}

}  // namespace

int main() {
    const std::string input = read_all(stdin);
    std::string_view rest{input};

    const auto capacity = parse_size(next_line(rest));
    if (!capacity || *capacity == 0) {
        std::cerr << "error: invalid capacity\n";
        return 1;
    }

    LruCache cache{*capacity};
    std::string out;
    out.reserve(1 << 20);
    while (!rest.empty()) {
        execute(cache, next_line(rest), out);
    }

    std::fwrite(out.data(), 1, out.size(), stdout);
    return 0;
}
