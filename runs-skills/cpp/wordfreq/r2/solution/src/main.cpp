// wordfreq: print the 10 most frequent ASCII-letter words read from stdin.
#include <algorithm>
#include <array>
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <string>
#include <string_view>
#include <unordered_map>
#include <utility>
#include <vector>

namespace {

constexpr std::size_t kTopN = 10;
constexpr std::size_t kChunkSize = 1 << 16;

struct StringHash {
    using is_transparent = void;
    [[nodiscard]] std::size_t operator()(std::string_view s) const noexcept {
        return std::hash<std::string_view>{}(s);
    }
};

using WordCounts = std::unordered_map<std::string, std::uint64_t, StringHash, std::equal_to<>>;

[[nodiscard]] constexpr bool is_ascii_letter(unsigned char c) noexcept {
    return (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z');
}

[[nodiscard]] constexpr char to_lower_ascii(unsigned char c) noexcept {
    return static_cast<char>(c | 0x20U);  // only called on ASCII letters
}

// Streams bytes, splitting them into lowercase words and counting each one.
class WordCounter {
public:
    void feed(std::string_view chunk) {
        for (const char ch : chunk) {
            const auto c = static_cast<unsigned char>(ch);
            if (is_ascii_letter(c)) {
                current_.push_back(to_lower_ascii(c));
            } else {
                flush();
            }
        }
    }

    [[nodiscard]] WordCounts finish() && {
        flush();
        return std::move(counts_);
    }

private:
    void flush() {
        if (current_.empty()) {
            return;
        }
        if (auto it = counts_.find(std::string_view{current_}); it != counts_.end()) {
            ++it->second;
        } else {
            counts_.emplace(current_, 1);
        }
        current_.clear();
    }

    WordCounts counts_;
    std::string current_;
};

[[nodiscard]] WordCounts count_stdin() {
    WordCounter counter;
    std::array<char, kChunkSize> buffer{};
    for (;;) {
        const std::size_t n = std::fread(buffer.data(), 1, buffer.size(), stdin);
        counter.feed(std::string_view{buffer.data(), n});
        if (n < buffer.size()) {
            break;  // EOF or read error
        }
    }
    return std::move(counter).finish();
}

using Entry = std::pair<std::string_view, std::uint64_t>;

[[nodiscard]] std::vector<Entry> top_words(const WordCounts& counts, std::size_t limit) {
    std::vector<Entry> entries(counts.begin(), counts.end());
    const auto by_rank = [](const Entry& a, const Entry& b) {
        if (a.second != b.second) {
            return a.second > b.second;
        }
        return a.first < b.first;
    };
    const auto middle = entries.begin() + static_cast<std::ptrdiff_t>(std::min(limit, entries.size()));
    std::partial_sort(entries.begin(), middle, entries.end(), by_rank);
    entries.erase(middle, entries.end());
    return entries;
}

}  // namespace

int main() {
    const WordCounts counts = count_stdin();
    std::string out;
    for (const auto& [word, count] : top_words(counts, kTopN)) {
        out += std::to_string(count);
        out += ' ';
        out += word;
        out += '\n';
    }
    std::fwrite(out.data(), 1, out.size(), stdout);
    return 0;
}
