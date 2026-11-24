// wordfreq: print the 10 most frequent ASCII-letter words read from stdin.
#include <algorithm>
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

using Counts = std::unordered_map<std::string, std::uint64_t>;

constexpr bool is_ascii_letter(unsigned char c) noexcept {
    return (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z');
}

constexpr char to_lower_ascii(unsigned char c) noexcept {
    return static_cast<char>(c | 0x20);  // only valid for ASCII letters
}

// Tokenizes a byte stream into lowercase words, tolerating words split across chunks.
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

    void finish() { flush(); }

    [[nodiscard]] const Counts& counts() const noexcept { return counts_; }

private:
    void flush() {
        if (current_.empty()) return;
        if (auto it = counts_.find(current_); it != counts_.end()) {
            ++it->second;
        } else {
            counts_.emplace(current_, 1);
        }
        current_.clear();
    }

    Counts counts_;
    std::string current_;
};

std::vector<std::pair<std::string_view, std::uint64_t>> top_words(const Counts& counts, std::size_t n) {
    std::vector<std::pair<std::string_view, std::uint64_t>> entries;
    entries.reserve(counts.size());
    for (const auto& [word, count] : counts) entries.emplace_back(word, count);

    const auto by_rank = [](const auto& a, const auto& b) {
        if (a.second != b.second) return a.second > b.second;
        return a.first < b.first;
    };
    const auto k = std::min(n, entries.size());
    std::partial_sort(entries.begin(), entries.begin() + static_cast<std::ptrdiff_t>(k), entries.end(), by_rank);
    entries.resize(k);
    return entries;
}

}  // namespace

int main() {
    WordCounter counter;
    std::vector<char> buffer(kChunkSize);
    for (;;) {
        const std::size_t got = std::fread(buffer.data(), 1, buffer.size(), stdin);
        if (got > 0) counter.feed(std::string_view(buffer.data(), got));
        if (got < buffer.size()) break;
    }
    counter.finish();

    std::string out;
    for (const auto& [word, count] : top_words(counter.counts(), kTopN)) {
        out += std::to_string(count);
        out += ' ';
        out += word;
        out += '\n';
    }
    std::fwrite(out.data(), 1, out.size(), stdout);
    return 0;
}
