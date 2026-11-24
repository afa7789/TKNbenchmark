#include "http.hpp"

#include <algorithm>
#include <cctype>

namespace kvhttp::http {

namespace {

constexpr std::string_view kCrlf = "\r\n";

std::string_view trim(std::string_view s) {
    constexpr std::string_view ws = " \t";
    const auto begin = s.find_first_not_of(ws);
    if (begin == std::string_view::npos) {
        return {};
    }
    const auto end = s.find_last_not_of(ws);
    return s.substr(begin, end - begin + 1);
}

bool is_token_char(unsigned char c) {
    if (std::isalnum(c)) {
        return true;
    }
    constexpr std::string_view extra = "!#$%&'*+-.^_`|~";
    return extra.find(static_cast<char>(c)) != std::string_view::npos;
}

bool is_token(std::string_view s) {
    return !s.empty() && std::all_of(s.begin(), s.end(), [](char c) {
        return is_token_char(static_cast<unsigned char>(c));
    });
}

}  // namespace

bool iequals(std::string_view a, std::string_view b) {
    return a.size() == b.size() &&
           std::equal(a.begin(), a.end(), b.begin(), [](char x, char y) {
               return std::tolower(static_cast<unsigned char>(x)) ==
                      std::tolower(static_cast<unsigned char>(y));
           });
}

std::optional<std::string_view> Request::header(std::string_view name) const {
    for (const auto& [key, value] : headers) {
        if (iequals(key, name)) {
            return value;
        }
    }
    return std::nullopt;
}

std::string_view reason_phrase(int status) {
    switch (status) {
        case 200: return "OK";
        case 201: return "Created";
        case 204: return "No Content";
        case 400: return "Bad Request";
        case 404: return "Not Found";
        case 405: return "Method Not Allowed";
        case 408: return "Request Timeout";
        case 411: return "Length Required";
        case 413: return "Content Too Large";
        case 431: return "Request Header Fields Too Large";
        case 500: return "Internal Server Error";
        case 501: return "Not Implemented";
        case 505: return "HTTP Version Not Supported";
        default: return "Unknown";
    }
}

std::string Response::serialize_head() const {
    std::string out;
    out.reserve(128 + headers.size() * 32);
    out += "HTTP/1.1 ";
    out += std::to_string(status);
    out += ' ';
    out += reason_phrase(status);
    out += kCrlf;
    for (const auto& [key, value] : headers) {
        out += key;
        out += ": ";
        out += value;
        out += kCrlf;
    }
    // 204 responses must not carry a body; Content-Length is omitted there.
    if (status != 204) {
        out += "Content-Length: ";
        out += std::to_string(body.size());
        out += kCrlf;
    }
    out += "Connection: close";
    out += kCrlf;
    out += kCrlf;
    return out;
}

std::optional<ParsedHead> parse_head(std::string_view data) {
    const auto head_end = data.find("\r\n\r\n");
    if (head_end == std::string_view::npos) {
        return std::nullopt;
    }
    std::string_view head = data.substr(0, head_end);

    ParsedHead result;
    result.head_size = head_end + 4;

    // Request line: METHOD SP request-target SP HTTP-version
    const auto line_end = head.find(kCrlf);
    const std::string_view request_line = head.substr(0, line_end);
    const auto sp1 = request_line.find(' ');
    if (sp1 == std::string_view::npos) {
        return std::nullopt;
    }
    const auto sp2 = request_line.find(' ', sp1 + 1);
    if (sp2 == std::string_view::npos) {
        return std::nullopt;
    }
    const std::string_view method = request_line.substr(0, sp1);
    const std::string_view target = request_line.substr(sp1 + 1, sp2 - sp1 - 1);
    const std::string_view version = request_line.substr(sp2 + 1);
    if (!is_token(method) || target.empty() || !version.starts_with("HTTP/1.")) {
        return std::nullopt;
    }
    result.request.method = method;
    result.request.target = target;

    // Header fields.
    std::string_view rest =
        line_end == std::string_view::npos ? std::string_view{} : head.substr(line_end + 2);
    while (!rest.empty()) {
        const auto eol = rest.find(kCrlf);
        const std::string_view line = rest.substr(0, eol);
        rest = eol == std::string_view::npos ? std::string_view{} : rest.substr(eol + 2);

        const auto colon = line.find(':');
        if (colon == std::string_view::npos) {
            return std::nullopt;
        }
        const std::string_view name = line.substr(0, colon);
        if (!is_token(name)) {
            return std::nullopt;
        }
        result.request.headers.emplace_back(std::string(name),
                                            std::string(trim(line.substr(colon + 1))));
    }
    return result;
}

}  // namespace kvhttp::http
