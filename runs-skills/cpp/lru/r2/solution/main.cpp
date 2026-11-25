#include <charconv>
#include <cstddef>
#include <cstdio>
#include <iostream>
#include <iterator>
#include <string>
#include <string_view>

#include "lru_cache.hpp"

namespace {

std::string read_all(std::FILE* in) {
    std::string data;
    char buf[1 << 16];
    std::size_t n = 0;
    while ((n = std::fread(buf, 1, sizeof buf, in)) > 0) data.append(buf, n);
    return data;
}

// Splits `text` into lines, tolerating a missing final newline and CRLF endings.
class LineReader {
public:
    explicit LineReader(std::string_view text) : rest_(text) {}

    bool next(std::string_view& line) {
        if (rest_.empty()) return false;
        const auto nl = rest_.find('\n');
        line = rest_.substr(0, nl);
        rest_ = nl == std::string_view::npos ? std::string_view{} : rest_.substr(nl + 1);
        if (line.ends_with('\r')) line.remove_suffix(1);
        return true;
    }

private:
    std::string_view rest_;
};

// Pops the next space-separated token from `s`.
std::string_view take_token(std::string_view& s) {
    const auto sp = s.find(' ');
    const auto tok = s.substr(0, sp);
    s = sp == std::string_view::npos ? std::string_view{} : s.substr(sp + 1);
    return tok;
}

}  // namespace

int main() {
    const std::string input = read_all(stdin);
    LineReader lines(input);

    std::string_view line;
    if (!lines.next(line)) return 0;
    std::size_t capacity = 0;
    std::from_chars(line.data(), line.data() + line.size(), capacity);

    LruCache cache(capacity);
    std::string out;
    out.reserve(1 << 20);

    while (lines.next(line)) {
        const auto cmd = take_token(line);
        if (cmd == "SET") {
            const auto key = take_token(line);
            const auto value = take_token(line);
            cache.set(key, value);
        } else if (cmd == "GET") {
            const auto value = cache.get(take_token(line));
            out.append(value ? *value : std::string_view{"NULL"});
            out.push_back('\n');
        } else if (cmd == "DEL") {
            out.append(cache.erase(take_token(line)) ? "1\n" : "0\n");
        } else if (cmd == "SIZE") {
            char buf[24];
            const auto res = std::to_chars(buf, buf + sizeof buf, cache.size());
            out.append(buf, res.ptr);
            out.push_back('\n');
        }
    }

    std::fwrite(out.data(), 1, out.size(), stdout);
    return std::fflush(stdout) == 0 ? 0 : 1;
}
