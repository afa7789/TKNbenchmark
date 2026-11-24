#include "http.hpp"

#include <sys/socket.h>
#include <sys/types.h>

#include <algorithm>
#include <cctype>
#include <cerrno>
#include <charconv>

namespace kvhttp {
namespace {

bool iequals(std::string_view a, std::string_view b) {
    return a.size() == b.size() &&
           std::equal(a.begin(), a.end(), b.begin(), [](unsigned char x, unsigned char y) {
               return std::tolower(x) == std::tolower(y);
           });
}

std::string_view trim(std::string_view s) {
    while (!s.empty() && (s.front() == ' ' || s.front() == '\t')) s.remove_prefix(1);
    while (!s.empty() && (s.back() == ' ' || s.back() == '\t')) s.remove_suffix(1);
    return s;
}

// Buffered reader over a socket file descriptor.
class SocketReader {
public:
    explicit SocketReader(int fd) : fd_(fd) {}

    // Reads more bytes into the buffer; returns false on EOF.
    bool fill() {
        char chunk[16 * 1024];
        for (;;) {
            ssize_t n = ::recv(fd_, chunk, sizeof chunk, 0);
            if (n > 0) {
                buf_.append(chunk, static_cast<std::size_t>(n));
                return true;
            }
            if (n == 0) return false;
            if (errno == EINTR) continue;
            throw HttpError{408};  // timeout or connection error
        }
    }

    // Returns the next CRLF-terminated line (without terminator).
    std::string read_line(std::size_t limit) {
        for (;;) {
            if (auto pos = buf_.find("\r\n", pos_); pos != std::string::npos) {
                std::string line = buf_.substr(pos_, pos - pos_);
                pos_ = pos + 2;
                return line;
            }
            if (buf_.size() - pos_ > limit) throw HttpError{431};
            if (!fill()) throw HttpError{400};
        }
    }

    void read_exact(std::size_t n, std::string& out) {
        while (buf_.size() - pos_ < n) {
            if (!fill()) throw HttpError{400};
        }
        out.append(buf_, pos_, n);
        pos_ += n;
    }

private:
    int fd_;
    std::string buf_;
    std::size_t pos_ = 0;
};

std::size_t parse_size(std::string_view s, int base) {
    std::size_t value = 0;
    auto [ptr, ec] = std::from_chars(s.data(), s.data() + s.size(), value, base);
    if (ec != std::errc{} || ptr != s.data() + s.size() || s.empty()) throw HttpError{400};
    return value;
}

void read_chunked_body(SocketReader& reader, std::string& body) {
    for (;;) {
        std::string line = reader.read_line(kMaxHeaderBytes);
        std::string_view size_part = line;
        if (auto semi = size_part.find(';'); semi != std::string_view::npos) {
            size_part = size_part.substr(0, semi);
        }
        std::size_t size = parse_size(trim(size_part), 16);
        if (size == 0) break;
        if (size > kMaxBodyBytes || body.size() + size > kMaxBodyBytes) throw HttpError{413};
        reader.read_exact(size, body);
        if (!reader.read_line(0).empty()) throw HttpError{400};
    }
    // Trailer section, terminated by an empty line.
    std::size_t total = 0;
    for (;;) {
        std::string line = reader.read_line(kMaxHeaderBytes);
        if (line.empty()) break;
        total += line.size();
        if (total > kMaxHeaderBytes) throw HttpError{431};
    }
}

bool send_all(int fd, std::string_view data) {
    while (!data.empty()) {
        ssize_t n = ::send(fd, data.data(), data.size(), 0);
        if (n < 0) {
            if (errno == EINTR) continue;
            return false;
        }
        data.remove_prefix(static_cast<std::size_t>(n));
    }
    return true;
}

}  // namespace

std::optional<std::string_view> Request::header(std::string_view name) const {
    for (const auto& [k, v] : headers) {
        if (iequals(k, name)) return std::string_view(v);
    }
    return std::nullopt;
}

std::optional<Request> read_request(int fd) {
    SocketReader reader(fd);
    if (!reader.fill()) return std::nullopt;

    Request req;
    std::size_t header_bytes = 0;

    std::string request_line = reader.read_line(kMaxHeaderBytes);
    // Tolerate stray blank lines before the request line (RFC 9112 §2.2).
    while (request_line.empty()) request_line = reader.read_line(kMaxHeaderBytes);
    header_bytes += request_line.size();

    std::string_view rl = request_line;
    auto sp1 = rl.find(' ');
    auto sp2 = sp1 == std::string_view::npos ? sp1 : rl.find(' ', sp1 + 1);
    if (sp2 == std::string_view::npos || sp1 == 0 || sp2 == sp1 + 1) throw HttpError{400};
    req.method = std::string(rl.substr(0, sp1));
    req.target = std::string(rl.substr(sp1 + 1, sp2 - sp1 - 1));
    if (!rl.substr(sp2 + 1).starts_with("HTTP/")) throw HttpError{400};

    for (;;) {
        std::string line = reader.read_line(kMaxHeaderBytes);
        if (line.empty()) break;
        header_bytes += line.size();
        if (header_bytes > kMaxHeaderBytes) throw HttpError{431};
        std::string_view lv = line;
        auto colon = lv.find(':');
        if (colon == std::string_view::npos || colon == 0) throw HttpError{400};
        req.headers.emplace_back(std::string(lv.substr(0, colon)),
                                 std::string(trim(lv.substr(colon + 1))));
    }

    if (auto te = req.header("Transfer-Encoding")) {
        if (!iequals(trim(*te), "chunked")) throw HttpError{501};
        read_chunked_body(reader, req.body);
    } else if (auto cl = req.header("Content-Length")) {
        std::size_t length = parse_size(trim(*cl), 10);
        if (length > kMaxBodyBytes) throw HttpError{413};
        req.body.reserve(length);
        reader.read_exact(length, req.body);
    }
    return req;
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
        case 413: return "Content Too Large";
        case 431: return "Request Header Fields Too Large";
        case 500: return "Internal Server Error";
        case 501: return "Not Implemented";
        default: return "Unknown";
    }
}

bool write_response(int fd, const Response& response) {
    std::string head;
    head.reserve(160);
    head += "HTTP/1.1 ";
    head += std::to_string(response.status);
    head += ' ';
    head += reason_phrase(response.status);
    head += "\r\n";
    if (!response.content_type.empty()) {
        head += "Content-Type: ";
        head += response.content_type;
        head += "\r\n";
    }
    // 204 must not carry a body or Content-Length framing; everything else
    // advertises its exact length.
    if (response.status != 204) {
        head += "Content-Length: ";
        head += std::to_string(response.body.size());
        head += "\r\n";
    }
    head += "Connection: close\r\n\r\n";

    if (response.body.size() < 16 * 1024) {
        head += response.body;
        return send_all(fd, head);
    }
    return send_all(fd, head) && send_all(fd, response.body);
}

}  // namespace kvhttp
