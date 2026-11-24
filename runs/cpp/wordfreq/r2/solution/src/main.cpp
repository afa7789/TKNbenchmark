// wordfreq: print the 10 most frequent ASCII words read from standard input.

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <functional>
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
    std::size_t operator()(std::string_view s) const noexcept {
        return std::hash<std::string_view>{}(s);
    }
};

using WordCounts = std::unordered_map<std::string, std::uint64_t, StringHash, std::equal_to<>>;

constexpr bool isAsciiLetter(unsigned char c) noexcept {
    return (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z');
}

constexpr char toLowerAscii(unsigned char c) noexcept {
    return static_cast<char>(c >= 'A' && c <= 'Z' ? c + ('a' - 'A') : c);
}

void addWord(WordCounts& counts, std::string_view word) {
    if (auto it = counts.find(word); it != counts.end()) {
        ++it->second;
    } else {
        counts.emplace(word, 1);
    }
}

// Streams stdin, accumulating lowercase words. A word may straddle chunk
// boundaries, so the in-progress word is carried across reads.
WordCounts countWords(std::FILE* in) {
    WordCounts counts;
    std::vector<unsigned char> buffer(kChunkSize);
    std::string current;

    std::size_t n;
    while ((n = std::fread(buffer.data(), 1, buffer.size(), in)) > 0) {
        for (std::size_t i = 0; i < n; ++i) {
            const unsigned char c = buffer[i];
            if (isAsciiLetter(c)) {
                current.push_back(toLowerAscii(c));
            } else if (!current.empty()) {
                addWord(counts, current);
                current.clear();
            }
        }
    }
    if (!current.empty()) {
        addWord(counts, current);
    }
    return counts;
}

using Entry = std::pair<std::string_view, std::uint64_t>;

std::vector<Entry> topWords(const WordCounts& counts, std::size_t limit) {
    std::vector<Entry> entries(counts.begin(), counts.end());
    const auto byRank = [](const Entry& a, const Entry& b) {
        if (a.second != b.second) return a.second > b.second;
        return a.first < b.first;
    };
    const std::size_t k = std::min(limit, entries.size());
    std::partial_sort(entries.begin(), entries.begin() + static_cast<std::ptrdiff_t>(k),
                      entries.end(), byRank);
    entries.resize(k);
    return entries;
}

}  // namespace

int main() {
    const WordCounts counts = countWords(stdin);
    for (const auto& [word, count] : topWords(counts, kTopN)) {
        std::printf("%llu %.*s\n", static_cast<unsigned long long>(count),
                    static_cast<int>(word.size()), word.data());
    }
    return 0;
}
