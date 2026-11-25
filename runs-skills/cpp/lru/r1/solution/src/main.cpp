// Reads an LRU cache capacity and a stream of commands from stdin and writes
// the results of GET, DEL and SIZE to stdout. See SPEC.md.

#include "lru_cache.hpp"

#include <charconv>
#include <cstddef>
#include <cstdio>
#include <optional>
#include <string>
#include <string_view>

namespace {

std::string read_all(std::FILE* in) {
    std::string data;
    std::size_t used = 0;
    std::size_t capacity = 1 << 16;
    while (true) {
        data.resize(capacity);
        const std::size_t got = std::fread(data.data() + used, 1, capacity - used, in);
        used += got;
        if (used < capacity) {
            if (got == 0 || std::feof(in) || std::ferror(in)) {
                break;
            }
            continue;
        }
        capacity *= 2;
    }
    data.resize(used);
    return data;
}

// Splits off the next line (without its terminator) from `rest`.
std::string_view next_line(std::string_view& rest) {
    const auto pos = rest.find('\n');
    std::string_view line = rest.substr(0, pos);
    rest = pos == std::string_view::npos ? std::string_view{} : rest.substr(pos + 1);
    if (line.ends_with('\r')) {
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
    while (!s.empty() && (s.front() == ' ' || s.front() == '\t')) s.remove_prefix(1);
    while (!s.empty() && (s.back() == ' ' || s.back() == '\t')) s.remove_suffix(1);
    std::size_t value{};
    const auto [end, ec] = std::from_chars(s.data(), s.data() + s.size(), value);
    if (ec != std::errc{} || end != s.data() + s.size()) {
        return std::nullopt;
    }
    return value;
}

void run(std::string_view input, std::string& out) {
    const auto capacity = parse_size(next_line(input));
    if (!capacity) {
        return;
    }
    LruCache cache(*capacity);

    while (!input.empty()) {
        std::string_view args = next_line(input);
        const std::string_view command = next_token(args);
        if (command == "SET") {
            const std::string_view key = next_token(args);
            const std::string_view value = next_token(args);
            cache.set(key, value);
        } else if (command == "GET") {
            const auto value = cache.get(next_token(args));
            out.append(value ? *value : std::string_view{"NULL"});
            out.push_back('\n');
        } else if (command == "DEL") {
            out.append(cache.erase(next_token(args)) ? "1\n" : "0\n");
        } else if (command == "SIZE") {
            out.append(std::to_string(cache.size()));
            out.push_back('\n');
        }
    }
}

}  // namespace

int main() {
    const std::string input = read_all(stdin);
    std::string out;
    out.reserve(input.size() / 2);
    run(input, out);
    std::fwrite(out.data(), 1, out.size(), stdout);
    return 0;
}
