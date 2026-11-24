#include "http.hpp"

#include <sys/socket.h>
#include <sys/uio.h>

#include <algorithm>
#include <array>
#include <cctype>
#include <cerrno>
#include <charconv>
#include <string_view>

namespace kvhttp {

namespace {

constexpr std::string_view kCrlf = "\r\n";
constexpr std::string_view kHeaderEnd = "\r\n\r\n";

bool iequals(std::string_view a, std::string_view b) {
    return std::ranges::equal(a, b, [](unsigned char x, unsigned char y) {
        return std::tolower(x) == std::tolower(y);
    });
}

std::string_view trim(std::string_view s) {
    constexpr std::string_view ws = " \t";
    const auto first = s.find_first_not_of(ws);
    if (first == std::string_view::npos) return {};
    const auto last = s.find_last_not_of(ws);
    return s.substr(first, last - first + 1);
}

// recv() that retries on EINTR. Returns bytes read, 0 on EOF, -1 on error.
ssize_t recv_some(int fd, char* buf, std::size_t len) {
    for (;;) {
        const ssize_t n = ::recv(fd, buf, len, 0);
        if (n >= 0 || errno != EINTR) return n;
    }
}

// Reads and throws away `remaining` bytes so the peer sees a clean close
// rather than a reset when we reply without consuming its body.
void discard(int fd, std::size_t remaining) {
    std::array<char, 16 * 1024> buf{};
    while (remaining > 0) {
        const ssize_t n = recv_some(fd, buf.data(), std::min(buf.size(), remaining));
        if (n <= 0) return;
        remaining -= static_cast<std::size_t>(n);
    }
}

ReadResult fail(int status) { return {std::nullopt, Response::empty(status)}; }

}  // namespace

Response Response::make(int status, std::string body, std::string content_type) {
    Response r;
    r.status = status;
    r.headers.emplace_back("Content-Type", std::move(content_type));
    r.body = std::make_shared<const std::string>(std::move(body));
    return r;
}

Response Response::empty(int status) {
    Response r;
    r.status = status;
    return r;
}

const char* reason_phrase(int status) {
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

ReadResult read_request(int fd, const Limits& limits) {
    std::string buf;
    std::array<char, 16 * 1024> chunk{};
    std::size_t header_end = std::string::npos;

    while (header_end == std::string::npos) {
        if (buf.size() > limits.max_header_bytes) return fail(431);
        const ssize_t n = recv_some(fd, chunk.data(), chunk.size());
        if (n <= 0) return {};  // peer closed or timed out: nothing to answer
        const std::size_t search_from = buf.size() >= 3 ? buf.size() - 3 : 0;
        buf.append(chunk.data(), static_cast<std::size_t>(n));
        header_end = buf.find(kHeaderEnd, search_from);
    }
    if (header_end > limits.max_header_bytes) return fail(431);

    const std::string_view head(buf.data(), header_end);
    const auto line_end = head.find(kCrlf);
    const std::string_view request_line = head.substr(0, line_end);

    // request-line = method SP request-target SP HTTP-version
    const auto sp1 = request_line.find(' ');
    const auto sp2 = sp1 == std::string_view::npos ? sp1 : request_line.find(' ', sp1 + 1);
    if (sp2 == std::string_view::npos || sp1 == 0 || sp2 == sp1 + 1) return fail(400);
    const std::string_view version = request_line.substr(sp2 + 1);
    if (!version.starts_with("HTTP/1.")) return fail(version.starts_with("HTTP/") ? 505 : 400);

    Request req;
    req.method = request_line.substr(0, sp1);
    req.target = request_line.substr(sp1 + 1, sp2 - sp1 - 1);

    std::optional<std::size_t> content_length;
    std::string_view rest =
        line_end == std::string_view::npos ? std::string_view{} : head.substr(line_end + 2);
    while (!rest.empty()) {
        const auto eol = rest.find(kCrlf);
        const std::string_view line = rest.substr(0, eol);
        rest = eol == std::string_view::npos ? std::string_view{} : rest.substr(eol + 2);

        const auto colon = line.find(':');
        if (colon == std::string_view::npos || colon == 0) return fail(400);
        const std::string_view name = line.substr(0, colon);
        const std::string_view value = trim(line.substr(colon + 1));

        if (iequals(name, "Content-Length")) {
            std::size_t len = 0;
            const auto [ptr, ec] = std::from_chars(value.data(), value.data() + value.size(), len);
            if (ec != std::errc{} || ptr != value.data() + value.size() || value.empty())
                return fail(400);
            if (content_length && *content_length != len) return fail(400);
            content_length = len;
        } else if (iequals(name, "Transfer-Encoding")) {
            return fail(501);
        }
    }

    const std::size_t length = content_length.value_or(0);
    std::string_view already(buf.data() + header_end + kHeaderEnd.size(),
                             buf.size() - header_end - kHeaderEnd.size());
    if (length > limits.max_body_bytes) {
        if (already.size() < length) discard(fd, length - already.size());
        return fail(413);
    }

    req.body.reserve(length);
    req.body.append(already.substr(0, std::min(already.size(), length)));
    while (req.body.size() < length) {
        const std::size_t want = std::min(chunk.size(), length - req.body.size());
        const ssize_t n = recv_some(fd, chunk.data(), want);
        if (n <= 0) return {};  // truncated body: peer is gone
        req.body.append(chunk.data(), static_cast<std::size_t>(n));
    }
    return {std::move(req), std::nullopt};
}

bool write_response(int fd, const Response& response) {
    const std::size_t body_size = response.body ? response.body->size() : 0;

    std::string head;
    head.reserve(256);
    head += "HTTP/1.1 ";
    head += std::to_string(response.status);
    head += ' ';
    head += reason_phrase(response.status);
    head += kCrlf;
    for (const auto& [name, value] : response.headers) {
        head += name;
        head += ": ";
        head += value;
        head += kCrlf;
    }
    if (response.status != 204) {
        head += "Content-Length: ";
        head += std::to_string(body_size);
        head += kCrlf;
    }
    head += "Connection: close\r\n\r\n";

    std::array<iovec, 2> iov{{
        {head.data(), head.size()},
        {const_cast<char*>(response.body ? response.body->data() : nullptr), body_size},
    }};
    std::size_t iov_index = 0;
    while (iov_index < iov.size()) {
        if (iov[iov_index].iov_len == 0) {
            ++iov_index;
            continue;
        }
        const ssize_t n = ::writev(fd, iov.data() + iov_index,
                                   static_cast<int>(iov.size() - iov_index));
        if (n < 0) {
            if (errno == EINTR) continue;
            return false;
        }
        auto written = static_cast<std::size_t>(n);
        while (iov_index < iov.size() && written >= iov[iov_index].iov_len) {
            written -= iov[iov_index].iov_len;
            ++iov_index;
        }
        if (iov_index < iov.size()) {
            iov[iov_index].iov_base = static_cast<char*>(iov[iov_index].iov_base) + written;
            iov[iov_index].iov_len -= written;
        }
    }
    return true;
}

}  // namespace kvhttp
