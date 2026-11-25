#include "http.hpp"

#include <algorithm>
#include <charconv>
#include <format>
#include <iterator>

namespace kvhttp {
namespace {

constexpr char to_lower(char c) noexcept {
    return (c >= 'A' && c <= 'Z') ? static_cast<char>(c - 'A' + 'a') : c;
}

bool iequals(std::string_view a, std::string_view b) noexcept {
    return std::ranges::equal(a, b, [](char x, char y) { return to_lower(x) == to_lower(y); });
}

std::string_view trim(std::string_view s) noexcept {
    const auto first = s.find_first_not_of(" \t");
    if (first == std::string_view::npos) return {};
    const auto last = s.find_last_not_of(" \t");
    return s.substr(first, last - first + 1);
}

bool is_token(std::string_view s) noexcept {
    constexpr std::string_view extra = "!#$%&'*+-.^_`|~";
    return !s.empty() && std::ranges::all_of(s, [&](char c) {
        return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
               extra.find(c) != std::string_view::npos;
    });
}

// Calls fn for each comma-separated, trimmed element of a header value.
template <typename Fn>
void for_each_list_item(std::string_view value, Fn&& fn) {
    while (!value.empty()) {
        const auto comma = value.find(',');
        fn(trim(value.substr(0, comma)));
        if (comma == std::string_view::npos) break;
        value.remove_prefix(comma + 1);
    }
}

std::optional<std::size_t> parse_size(std::string_view s) noexcept {
    if (s.empty()) return std::nullopt;
    std::size_t value{};
    const auto [ptr, ec] = std::from_chars(s.data(), s.data() + s.size(), value);
    if (ec != std::errc{} || ptr != s.data() + s.size()) return std::nullopt;
    return value;
}

std::string_view reason_phrase(int status) noexcept {
    switch (status) {
        case 200: return "OK";
        case 201: return "Created";
        case 204: return "No Content";
        case 400: return "Bad Request";
        case 404: return "Not Found";
        case 405: return "Method Not Allowed";
        case 408: return "Request Timeout";
        case 413: return "Content Too Large";
        case 431: return "Request Header Fields Too Large";
        case 500: return "Internal Server Error";
        case 501: return "Not Implemented";
        case 505: return "HTTP Version Not Supported";
        default: return "Unknown";
    }
}

}  // namespace

std::optional<RequestHead> parse_head(std::string_view head) {
    auto next_line = [&head]() -> std::optional<std::string_view> {
        if (head.empty()) return std::nullopt;
        const auto eol = head.find("\r\n");
        const auto line = head.substr(0, eol);
        head.remove_prefix(eol == std::string_view::npos ? head.size() : eol + 2);
        return line;
    };

    const auto request_line = next_line();
    if (!request_line) return std::nullopt;

    // method SP request-target SP HTTP-version
    const auto sp1 = request_line->find(' ');
    const auto sp2 = request_line->rfind(' ');
    if (sp1 == std::string_view::npos || sp1 == sp2) return std::nullopt;
    const auto method = request_line->substr(0, sp1);
    const auto target = request_line->substr(sp1 + 1, sp2 - sp1 - 1);
    const auto version = request_line->substr(sp2 + 1);
    if (!is_token(method) || target.empty() || target.find(' ') != std::string_view::npos) {
        return std::nullopt;
    }
    if (version != "HTTP/1.1" && version != "HTTP/1.0") return std::nullopt;

    RequestHead result{
        .method = std::string(method),
        .target = std::string(target),
        .content_length = 0,
        .keep_alive = version == "HTTP/1.1",
        .chunked = false,
    };

    std::optional<std::size_t> content_length;
    while (const auto line = next_line()) {
        const auto colon = line->find(':');
        if (colon == std::string_view::npos) return std::nullopt;
        const auto name = line->substr(0, colon);
        const auto value = trim(line->substr(colon + 1));
        if (!is_token(name)) return std::nullopt;

        if (iequals(name, "content-length")) {
            const auto parsed = parse_size(value);
            if (!parsed || (content_length && *content_length != *parsed)) return std::nullopt;
            content_length = parsed;
        } else if (iequals(name, "transfer-encoding")) {
            result.chunked = true;
        } else if (iequals(name, "connection")) {
            for_each_list_item(value, [&](std::string_view item) {
                if (iequals(item, "close")) result.keep_alive = false;
                else if (iequals(item, "keep-alive")) result.keep_alive = true;
            });
        }
    }
    // A message with both framings is ambiguous (request smuggling); reject it.
    if (result.chunked && content_length) return std::nullopt;
    result.content_length = content_length.value_or(0);
    return result;
}

std::string serialize(const Response& response, bool keep_alive) {
    std::string out;
    out.reserve(128 + response.body.size());
    auto it = std::back_inserter(out);
    std::format_to(it, "HTTP/1.1 {} {}\r\n", response.status, reason_phrase(response.status));
    // 204 responses must not carry a body or a Content-Length.
    if (response.status != 204) {
        std::format_to(it, "Content-Length: {}\r\n", response.body.size());
        if (!response.content_type.empty()) {
            std::format_to(it, "Content-Type: {}\r\n", response.content_type);
        }
    }
    out += keep_alive ? "Connection: keep-alive\r\n\r\n" : "Connection: close\r\n\r\n";
    if (response.status != 204) out += response.body;
    return out;
}

}  // namespace kvhttp
