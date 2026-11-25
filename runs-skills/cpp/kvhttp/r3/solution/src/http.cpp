#include "kvhttp/http.hpp"

#include <sys/socket.h>

#include <algorithm>
#include <array>
#include <cctype>
#include <cerrno>
#include <charconv>
#include <format>

#include "kvhttp/socket.hpp"

namespace kvhttp {
namespace {

bool iequals(std::string_view a, std::string_view b) noexcept {
    return std::ranges::equal(a, b, [](unsigned char x, unsigned char y) {
        return std::tolower(x) == std::tolower(y);
    });
}

std::string_view trim(std::string_view s) noexcept {
    constexpr std::string_view ws = " \t";
    const auto begin = s.find_first_not_of(ws);
    if (begin == std::string_view::npos) return {};
    const auto end = s.find_last_not_of(ws);
    return s.substr(begin, end - begin + 1);
}

// RFC 9110 token characters, used for methods and header names.
bool is_token(std::string_view s) noexcept {
    constexpr std::string_view extra = "!#$%&'*+-.^_`|~";
    return !s.empty() && std::ranges::all_of(s, [&](unsigned char c) {
        return std::isalnum(c) != 0 || extra.find(static_cast<char>(c)) != std::string_view::npos;
    });
}

std::optional<std::size_t> parse_size(std::string_view s, int base = 10) noexcept {
    std::size_t value{};
    const auto [end, ec] = std::from_chars(s.data(), s.data() + s.size(), value, base);
    if (s.empty() || ec != std::errc{} || end != s.data() + s.size()) return std::nullopt;
    return value;
}

Response with_type(int status, std::string body, std::string type) {
    Response res{.status = status, .headers = {}, .body = std::move(body)};
    res.headers.push_back({"Content-Type", std::move(type)});
    return res;
}

}  // namespace

std::optional<std::string_view> Request::header(std::string_view name) const {
    const auto it = std::ranges::find_if(headers, [&](const Header& h) { return iequals(h.name, name); });
    if (it == headers.end()) return std::nullopt;
    return it->value;
}

Response Response::text(int status, std::string body) {
    return with_type(status, std::move(body), "text/plain; charset=utf-8");
}

Response Response::json(int status, std::string body) {
    return with_type(status, std::move(body), "application/json");
}

Response Response::binary(int status, std::string body) {
    return with_type(status, std::move(body), "application/octet-stream");
}

std::optional<Request> RequestReader::read() {
    Request req;
    try {
        read_head(req);
        read_body(req);
    } catch (const PeerClosed&) {
        return std::nullopt;
    }
    return req;
}

bool RequestReader::fill() {
    if (pos_ > 0) {
        buf_.erase(0, pos_);
        pos_ = 0;
    }
    std::array<char, 16 * 1024> chunk{};
    for (;;) {
        const ssize_t n = ::recv(fd_, chunk.data(), chunk.size(), 0);
        if (n < 0 && errno == EINTR) continue;
        if (n <= 0) return false;
        buf_.append(chunk.data(), static_cast<std::size_t>(n));
        return true;
    }
}

std::string RequestReader::read_line() {
    std::size_t scanned = pos_;
    for (;;) {
        const auto nl = buf_.find('\n', scanned);
        if (nl != std::string::npos) {
            std::size_t end = nl;
            if (end > pos_ && buf_[end - 1] == '\r') --end;
            if (end - pos_ > limits_.max_line) throw HttpError(431, "header line too long");
            std::string line = buf_.substr(pos_, end - pos_);
            pos_ = nl + 1;
            return line;
        }
        if (buf_.size() - pos_ > limits_.max_line) throw HttpError(431, "header line too long");
        scanned = buf_.size();
        const std::size_t offset = scanned - pos_;
        if (!fill()) throw PeerClosed{};
        scanned = pos_ + offset;
    }
}

void RequestReader::read_exact(std::size_t n, std::string& out) {
    while (buf_.size() - pos_ < n) {
        const std::size_t available = buf_.size() - pos_;
        out.append(buf_, pos_, available);
        n -= available;
        pos_ = buf_.size();
        if (!fill()) throw PeerClosed{};
    }
    out.append(buf_, pos_, n);
    pos_ += n;
}

void RequestReader::read_head(Request& req) {
    std::string line = read_line();
    // RFC 9112 §2.2: ignore at least one empty line before the request line.
    while (line.empty()) line = read_line();

    const auto sp1 = line.find(' ');
    const auto sp2 = sp1 == std::string::npos ? sp1 : line.find(' ', sp1 + 1);
    if (sp2 == std::string::npos || line.find(' ', sp2 + 1) != std::string::npos) {
        throw HttpError(400, "malformed request line");
    }
    const std::string_view view = line;
    const auto method = view.substr(0, sp1);
    const auto target = view.substr(sp1 + 1, sp2 - sp1 - 1);
    const auto version = view.substr(sp2 + 1);

    if (!is_token(method)) throw HttpError(400, "invalid method");
    if (target.empty() || target.front() != '/') throw HttpError(400, "invalid request target");
    if (!version.starts_with("HTTP/1.")) {
        throw HttpError(version.starts_with("HTTP/") ? 505 : 400, "unsupported HTTP version");
    }

    req.method = method;
    req.path = target.substr(0, target.find('?'));

    for (;;) {
        std::string header_line = read_line();
        if (header_line.empty()) break;
        if (req.headers.size() >= limits_.max_headers) throw HttpError(431, "too many headers");
        const auto colon = header_line.find(':');
        if (colon == std::string::npos) throw HttpError(400, "malformed header");
        const std::string_view hv = header_line;
        const auto name = hv.substr(0, colon);
        if (!is_token(name)) throw HttpError(400, "invalid header name");
        req.headers.push_back({std::string(name), std::string(trim(hv.substr(colon + 1)))});
    }
}

void RequestReader::read_body(Request& req) {
    std::optional<std::size_t> content_length;
    bool chunked = false;
    for (const auto& h : req.headers) {
        if (iequals(h.name, "Content-Length")) {
            const auto n = parse_size(h.value);
            if (!n || (content_length && *content_length != *n)) throw HttpError(400, "invalid Content-Length");
            content_length = n;
        } else if (iequals(h.name, "Transfer-Encoding")) {
            if (!iequals(h.value, "chunked")) throw HttpError(501, "unsupported Transfer-Encoding");
            chunked = true;
        }
    }
    if (chunked && content_length) throw HttpError(400, "both Content-Length and Transfer-Encoding");

    if (chunked) {
        send_continue_if_expected(req);
        read_chunked_body(req.body);
    } else if (content_length && *content_length > 0) {
        if (*content_length > limits_.max_body) throw HttpError(413, "body too large");
        send_continue_if_expected(req);
        req.body.reserve(*content_length);
        read_exact(*content_length, req.body);
    }
}

void RequestReader::read_chunked_body(std::string& out) {
    for (;;) {
        const std::string line = read_line();
        std::string_view size_text = line;
        size_text = trim(size_text.substr(0, size_text.find(';')));  // drop chunk extensions
        const auto size = parse_size(size_text, 16);
        if (!size) throw HttpError(400, "invalid chunk size");
        if (*size == 0) break;
        if (*size > limits_.max_body - out.size()) throw HttpError(413, "body too large");
        read_exact(*size, out);
        if (!read_line().empty()) throw HttpError(400, "malformed chunk");
    }
    // Trailer section: skip until the terminating empty line.
    while (!read_line().empty()) {
    }
}

void RequestReader::send_continue_if_expected(const Request& req) {
    const auto expect = req.header("Expect");
    if (expect && iequals(*expect, "100-continue")) {
        constexpr std::string_view interim = "HTTP/1.1 100 Continue\r\n\r\n";
        if (!send_all(fd_, std::span(&interim, 1))) throw PeerClosed{};
    }
}

std::string_view reason_phrase(int status) noexcept {
    switch (status) {
        case 100: return "Continue";
        case 200: return "OK";
        case 201: return "Created";
        case 204: return "No Content";
        case 400: return "Bad Request";
        case 404: return "Not Found";
        case 405: return "Method Not Allowed";
        case 413: return "Content Too Large";
        case 431: return "Request Header Fields Too Large";
        case 500: return "Internal Server Error";
        case 501: return "Not Implemented";
        case 505: return "HTTP Version Not Supported";
        default: return "Unknown";
    }
}

std::string serialize_head(const Response& res) {
    std::string head = std::format("HTTP/1.1 {} {}\r\n", res.status, reason_phrase(res.status));
    for (const auto& h : res.headers) {
        head += std::format("{}: {}\r\n", h.name, h.value);
    }
    head += std::format("Content-Length: {}\r\nConnection: close\r\n\r\n", res.body.size());
    return head;
}

}  // namespace kvhttp
