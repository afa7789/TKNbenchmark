// LRU cache simulator: reads a capacity and a stream of commands from stdin
// and writes command results to stdout. See SPEC.md.

#include "lru_cache.hpp"

#include <charconv>
#include <cstddef>
#include <cstdio>
#include <iterator>
#include <string>
#include <string_view>

namespace {

// Reads the whole of `stream` in large chunks (much faster than iostreams).
std::string read_all(std::FILE* stream) {
    std::string data;
    std::size_t used = 0;
    constexpr std::size_t kChunk = std::size_t{1} << 16;
    for (;;) {
        data.resize(used + kChunk);
        const std::size_t got = std::fread(data.data() + used, 1, kChunk, stream);
        used += got;
        if (got < kChunk) {
            break;
        }
    }
    data.resize(used);
    return data;
}

// Splits `text` into lines on '\n', tolerating a missing final newline and
// stray '\r' before the newline.
class LineReader {
public:
    explicit LineReader(std::string_view text) : rest_(text) {}

    bool next(std::string_view& line) {
        if (rest_.empty()) {
            return false;
        }
        const auto nl = rest_.find('\n');
        line = rest_.substr(0, nl);
        rest_ = nl == std::string_view::npos ? std::string_view{} : rest_.substr(nl + 1);
        if (!line.empty() && line.back() == '\r') {
            line.remove_suffix(1);
        }
        return true;
    }

private:
    std::string_view rest_;
};

// Returns the next space-delimited token from `s`, advancing past it.
std::string_view next_token(std::string_view& s) {
    const auto start = s.find_first_not_of(' ');
    if (start == std::string_view::npos) {
        s = {};
        return {};
    }
    s.remove_prefix(start);
    const auto end = s.find(' ');
    const auto token = s.substr(0, end);
    s = end == std::string_view::npos ? std::string_view{} : s.substr(end);
    return token;
}

std::size_t parse_capacity(std::string_view line) {
    const auto token = next_token(line);
    std::size_t capacity = 0;
    std::from_chars(token.data(), token.data() + token.size(), capacity);
    return capacity;
}

void execute(LruCache& cache, std::string_view line, std::string& out) {
    const auto command = next_token(line);
    if (command == "SET") {
        const auto key = next_token(line);
        const auto value = next_token(line);
        if (!key.empty() && !value.empty()) {
            cache.set(key, value);
        }
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
        char buf[24];
        const auto [end, ec] = std::to_chars(std::begin(buf), std::end(buf), cache.size());
        out.append(buf, end);
        out.push_back('\n');
    }
    // Blank or unrecognised lines produce no output.
}

}  // namespace

int main() {
    const std::string input = read_all(stdin);
    LineReader lines(input);

    std::string_view line;
    if (!lines.next(line)) {
        return 0;
    }
    LruCache cache(parse_capacity(line));

    std::string out;
    out.reserve(1 << 20);
    while (lines.next(line)) {
        execute(cache, line, out);
    }

    std::fwrite(out.data(), 1, out.size(), stdout);
    std::fflush(stdout);
    return 0;
}
