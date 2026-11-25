// wordfreq: print the 10 most frequent ASCII words read from standard input.
#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <iostream>
#include <string>
#include <string_view>
#include <unordered_map>
#include <utility>
#include <vector>

namespace {

constexpr std::size_t kTopN = 10;

using Counts = std::unordered_map<std::string, std::uint64_t>;
using Entry = std::pair<std::string_view, std::uint64_t>;

[[nodiscard]] constexpr bool is_ascii_letter(unsigned char c) noexcept {
    return (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z');
}

[[nodiscard]] constexpr char to_lower_ascii(unsigned char c) noexcept {
    return static_cast<char>(c >= 'A' && c <= 'Z' ? c + ('a' - 'A') : c);
}

// Incrementally tokenizes bytes into lowercase words; words may span chunks.
class WordCounter {
public:
    void feed(std::string_view chunk) {
        for (const char ch : chunk) {
            const auto c = static_cast<unsigned char>(ch);
            if (is_ascii_letter(c)) {
                word_.push_back(to_lower_ascii(c));
            } else {
                flush();
            }
        }
    }

    // Commits any word in progress (call at end of input).
    void flush() {
        if (word_.empty()) return;
        if (auto it = counts_.find(word_); it != counts_.end()) {
            ++it->second;
        } else {
            counts_.emplace(word_, 1);
        }
        word_.clear();
    }

    [[nodiscard]] const Counts& counts() const noexcept { return counts_; }

private:
    Counts counts_;
    std::string word_;
};

[[nodiscard]] std::vector<Entry> top_words(const Counts& counts, std::size_t n) {
    std::vector<Entry> entries(counts.begin(), counts.end());
    const auto order = [](const Entry& a, const Entry& b) {
        if (a.second != b.second) return a.second > b.second;
        return a.first < b.first;
    };
    const std::size_t k = std::min(n, entries.size());
    std::partial_sort(entries.begin(), entries.begin() + static_cast<std::ptrdiff_t>(k),
                      entries.end(), order);
    entries.resize(k);
    return entries;
}

}  // namespace

int main() {
    std::ios::sync_with_stdio(false);

    WordCounter counter;
    std::vector<char> buffer(1 << 16);
    std::size_t got = 0;
    while ((got = std::fread(buffer.data(), 1, buffer.size(), stdin)) > 0) {
        counter.feed(std::string_view(buffer.data(), got));
    }
    counter.flush();

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
