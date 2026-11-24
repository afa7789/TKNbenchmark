// LRU cache simulator: reads a capacity and a stream of commands from stdin.
#include <cstddef>
#include <cstdio>
#include <functional>
#include <list>
#include <string>
#include <string_view>
#include <unordered_map>
#include <utility>

namespace {

struct StringHash {
    using is_transparent = void;
    std::size_t operator()(std::string_view s) const noexcept {
        return std::hash<std::string_view>{}(s);
    }
};

class LruCache {
public:
    explicit LruCache(std::size_t capacity) : capacity_(capacity) {
        index_.reserve(capacity + 1);
    }

    void set(std::string_view key, std::string_view value) {
        if (auto it = index_.find(key); it != index_.end()) {
            it->second->second.assign(value);
            touch(it->second);
            return;
        }
        entries_.emplace_front(std::string(key), std::string(value));
        index_.emplace(entries_.front().first, entries_.begin());
        if (entries_.size() > capacity_) {
            index_.erase(entries_.back().first);
            entries_.pop_back();
        }
    }

    // Returns nullptr on miss; the pointer is valid until the next mutation.
    const std::string* get(std::string_view key) {
        auto it = index_.find(key);
        if (it == index_.end()) return nullptr;
        touch(it->second);
        return &it->second->second;
    }

    bool erase(std::string_view key) {
        auto it = index_.find(key);
        if (it == index_.end()) return false;
        auto node = it->second;
        index_.erase(it);
        entries_.erase(node);
        return true;
    }

    std::size_t size() const noexcept { return entries_.size(); }

private:
    using Entry = std::pair<std::string, std::string>;
    using EntryList = std::list<Entry>;

    void touch(EntryList::iterator node) {
        entries_.splice(entries_.begin(), entries_, node);
    }

    std::size_t capacity_;
    EntryList entries_;  // front = most recently used
    // Keys view the strings owned by list nodes, which never move.
    std::unordered_map<std::string_view, EntryList::iterator, StringHash, std::equal_to<>> index_;
};

std::string readAll(std::FILE* in) {
    std::string data;
    char buf[1 << 16];
    std::size_t n;
    while ((n = std::fread(buf, 1, sizeof buf, in)) > 0) data.append(buf, n);
    return data;
}

// Splits off the next space-delimited token from `rest`.
std::string_view nextToken(std::string_view& rest) {
    const auto pos = rest.find(' ');
    const auto token = rest.substr(0, pos);
    rest = pos == std::string_view::npos ? std::string_view{} : rest.substr(pos + 1);
    return token;
}

class LineReader {
public:
    explicit LineReader(std::string_view data) : rest_(data) {}

    bool next(std::string_view& line) {
        if (rest_.empty()) return false;
        const auto pos = rest_.find('\n');
        line = rest_.substr(0, pos);
        rest_ = pos == std::string_view::npos ? std::string_view{} : rest_.substr(pos + 1);
        if (!line.empty() && line.back() == '\r') line.remove_suffix(1);
        return true;
    }

private:
    std::string_view rest_;
};

std::size_t parseCapacity(std::string_view s) {
    std::size_t value = 0;
    for (char c : s) {
        if (c < '0' || c > '9') break;
        value = value * 10 + static_cast<std::size_t>(c - '0');
    }
    return value;
}

}  // namespace

int main() {
    const std::string input = readAll(stdin);
    LineReader lines(input);

    std::string_view line;
    if (!lines.next(line)) return 0;
    LruCache cache(parseCapacity(line));

    std::string out;
    out.reserve(1 << 20);

    while (lines.next(line)) {
        std::string_view rest = line;
        const auto cmd = nextToken(rest);
        if (cmd == "SET") {
            const auto key = nextToken(rest);
            const auto value = nextToken(rest);
            cache.set(key, value);
        } else if (cmd == "GET") {
            if (const auto* value = cache.get(nextToken(rest))) {
                out += *value;
            } else {
                out += "NULL";
            }
            out += '\n';
        } else if (cmd == "DEL") {
            out += cache.erase(nextToken(rest)) ? "1\n" : "0\n";
        } else if (cmd == "SIZE") {
            out += std::to_string(cache.size());
            out += '\n';
        }
    }

    std::fwrite(out.data(), 1, out.size(), stdout);
    return 0;
}
