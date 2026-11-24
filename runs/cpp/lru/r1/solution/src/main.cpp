// LRU cache simulator: reads a capacity and a stream of commands from stdin.
#include <algorithm>
#include <charconv>
#include <cstddef>
#include <cstdio>
#include <list>
#include <optional>
#include <string>
#include <string_view>
#include <unordered_map>
#include <utility>

namespace {

class LruCache {
public:
    explicit LruCache(std::size_t capacity) : capacity_(capacity) {
        index_.reserve(std::min<std::size_t>(capacity + 1, 1u << 20));
    }

    void set(std::string_view key, std::string_view value) {
        if (auto it = index_.find(key); it != index_.end()) {
            it->second->value.assign(value);
            touch(it->second);
            return;
        }
        entries_.push_front(Entry{std::string(key), std::string(value)});
        index_.emplace(entries_.front().key, entries_.begin());
        if (entries_.size() > capacity_) {
            index_.erase(entries_.back().key);
            entries_.pop_back();
        }
    }

    // Returns a view valid until the next mutating call.
    std::optional<std::string_view> get(std::string_view key) {
        auto it = index_.find(key);
        if (it == index_.end()) return std::nullopt;
        touch(it->second);
        return std::string_view(it->second->value);
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
    struct Entry {
        std::string key;
        std::string value;
    };
    using List = std::list<Entry>;

    void touch(List::iterator node) { entries_.splice(entries_.begin(), entries_, node); }

    std::size_t capacity_;
    List entries_;  // front = most recently used
    // Keys view into the owning list node, whose storage is stable.
    std::unordered_map<std::string_view, List::iterator> index_;
};

std::string_view trim(std::string_view s) {
    while (!s.empty() && (s.back() == '\r' || s.back() == ' ' || s.back() == '\t')) s.remove_suffix(1);
    while (!s.empty() && (s.front() == ' ' || s.front() == '\t')) s.remove_prefix(1);
    return s;
}

// Splits off the next space-separated token from `s`.
std::string_view next_token(std::string_view& s) {
    const auto pos = s.find(' ');
    std::string_view tok = s.substr(0, pos);
    s = pos == std::string_view::npos ? std::string_view{} : s.substr(pos + 1);
    return tok;
}

std::string read_all(std::FILE* in) {
    std::string data;
    char buf[1 << 16];
    std::size_t n;
    while ((n = std::fread(buf, 1, sizeof buf, in)) > 0) data.append(buf, n);
    return data;
}

}  // namespace

int main() {
    const std::string input = read_all(stdin);
    std::string_view rest(input);

    auto next_line = [&rest]() -> std::optional<std::string_view> {
        if (rest.empty()) return std::nullopt;
        const auto pos = rest.find('\n');
        std::string_view line = rest.substr(0, pos);
        rest = pos == std::string_view::npos ? std::string_view{} : rest.substr(pos + 1);
        return trim(line);
    };

    std::size_t capacity = 0;
    if (auto line = next_line()) {
        std::from_chars(line->data(), line->data() + line->size(), capacity);
    }

    LruCache cache(capacity);
    std::string out;
    out.reserve(1u << 16);

    while (auto line = next_line()) {
        std::string_view args = *line;
        const std::string_view cmd = next_token(args);
        if (cmd == "SET") {
            const std::string_view key = next_token(args);
            const std::string_view value = next_token(args);
            cache.set(key, value);
        } else if (cmd == "GET") {
            const auto value = cache.get(next_token(args));
            out.append(value ? *value : std::string_view("NULL"));
            out.push_back('\n');
        } else if (cmd == "DEL") {
            out.append(cache.erase(next_token(args)) ? "1\n" : "0\n");
        } else if (cmd == "SIZE") {
            out.append(std::to_string(cache.size()));
            out.push_back('\n');
        }
    }

    std::fwrite(out.data(), 1, out.size(), stdout);
    return 0;
}
