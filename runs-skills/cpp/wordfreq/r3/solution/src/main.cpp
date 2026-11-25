// wordfreq: print the 10 most frequent ASCII words read from standard input.
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

using WordCounts = std::unordered_map<std::string_view, std::uint64_t>;
using Entry = std::pair<std::string_view, std::uint64_t>;

[[nodiscard]] std::string read_all(std::FILE* in) {
    std::string data;
    constexpr std::size_t kChunk = std::size_t{1} << 20;
    std::size_t used = 0;
    for (;;) {
        data.resize(used + kChunk);
        const std::size_t got = std::fread(data.data() + used, 1, kChunk, in);
        used += got;
        if (got < kChunk) break;
    }
    data.resize(used);
    return data;
}

[[nodiscard]] constexpr bool is_alpha(unsigned char c) noexcept {
    return static_cast<unsigned char>((c | 0x20U) - 'a') < 26U;
}

// Lowercases words in place and counts them. The returned views refer into `text`.
[[nodiscard]] WordCounts count_words(std::string& text) {
    WordCounts counts;
    counts.reserve(1 << 14);
    const std::size_t n = text.size();
    std::size_t i = 0;
    while (i < n) {
        while (i < n && !is_alpha(static_cast<unsigned char>(text[i]))) ++i;
        const std::size_t start = i;
        while (i < n && is_alpha(static_cast<unsigned char>(text[i]))) {
            text[i] = static_cast<char>(text[i] | 0x20);
            ++i;
        }
        if (i > start) ++counts[std::string_view(text).substr(start, i - start)];
    }
    return counts;
}

[[nodiscard]] std::vector<Entry> top_words(const WordCounts& counts, std::size_t limit) {
    std::vector<Entry> entries(counts.begin(), counts.end());
    const auto by_rank = [](const Entry& a, const Entry& b) {
        if (a.second != b.second) return a.second > b.second;
        return a.first < b.first;
    };
    const std::size_t k = std::min(limit, entries.size());
    std::partial_sort(entries.begin(), entries.begin() + static_cast<std::ptrdiff_t>(k),
                      entries.end(), by_rank);
    entries.resize(k);
    return entries;
}

}  // namespace

int main() {
    std::string text = read_all(stdin);
    const WordCounts counts = count_words(text);

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
