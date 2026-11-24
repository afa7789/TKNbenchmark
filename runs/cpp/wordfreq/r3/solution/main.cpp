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

std::string read_all(std::FILE* in) {
    std::string data;
    std::vector<char> chunk(1 << 16);
    std::size_t n = 0;
    while ((n = std::fread(chunk.data(), 1, chunk.size(), in)) > 0) {
        data.append(chunk.data(), n);
    }
    return data;
}

constexpr bool is_upper(unsigned char c) { return c >= 'A' && c <= 'Z'; }
constexpr bool is_lower(unsigned char c) { return c >= 'a' && c <= 'z'; }

// Lowercases `text` in place and counts each word. Keys are views into `text`,
// so the buffer must outlive the returned map.
std::unordered_map<std::string_view, std::uint64_t> count_words(std::string& text) {
    std::unordered_map<std::string_view, std::uint64_t> counts;
    counts.reserve(1 << 12);

    const std::size_t size = text.size();
    std::size_t i = 0;
    while (i < size) {
        while (i < size) {
            const auto c = static_cast<unsigned char>(text[i]);
            if (is_lower(c) || is_upper(c)) break;
            ++i;
        }
        const std::size_t start = i;
        while (i < size) {
            const auto c = static_cast<unsigned char>(text[i]);
            if (is_upper(c)) {
                text[i] = static_cast<char>(c - 'A' + 'a');
            } else if (!is_lower(c)) {
                break;
            }
            ++i;
        }
        if (i > start) {
            ++counts[std::string_view(text).substr(start, i - start)];
        }
    }
    return counts;
}

}  // namespace

int main() {
    std::string text = read_all(stdin);
    const auto counts = count_words(text);

    using Entry = std::pair<std::string_view, std::uint64_t>;
    std::vector<Entry> entries(counts.begin(), counts.end());

    const auto by_rank = [](const Entry& a, const Entry& b) {
        if (a.second != b.second) return a.second > b.second;
        return a.first < b.first;
    };
    const std::size_t top = std::min(kTopN, entries.size());
    std::partial_sort(entries.begin(), entries.begin() + static_cast<std::ptrdiff_t>(top),
                      entries.end(), by_rank);

    std::string out;
    for (std::size_t k = 0; k < top; ++k) {
        out += std::to_string(entries[k].second);
        out += ' ';
        out += entries[k].first;
        out += '\n';
    }
    std::fwrite(out.data(), 1, out.size(), stdout);
    return 0;
}
