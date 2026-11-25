#include "http.hpp"

#include <algorithm>
#include <charconv>
#include <format>

namespace kvhttp {
namespace {

constexpr char ascii_lower(char c) noexcept { return (c >= 'A' && c <= 'Z') ? static_cast<char>(c - 'A' + 'a') : c; }

bool iequals(std::string_view a, std::string_view b) noexcept {
  return std::ranges::equal(a, b, [](char x, char y) { return ascii_lower(x) == ascii_lower(y); });
}

std::string_view trim_ows(std::string_view s) noexcept {
  while (!s.empty() && (s.front() == ' ' || s.front() == '\t')) s.remove_prefix(1);
  while (!s.empty() && (s.back() == ' ' || s.back() == '\t')) s.remove_suffix(1);
  return s;
}

// RFC 9110 tchar.
bool is_token_char(char c) noexcept {
  if ((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9')) return true;
  return std::string_view{"!#$%&'*+-.^_`|~"}.find(c) != std::string_view::npos;
}

bool is_token(std::string_view s) noexcept { return !s.empty() && std::ranges::all_of(s, is_token_char); }

HttpError bad_request(std::string message) { return HttpError{400, std::move(message)}; }

}  // namespace

std::optional<std::string_view> RequestHead::header(std::string_view name) const {
  for (const auto& [key, value] : headers) {
    if (iequals(key, name)) return value;
  }
  return std::nullopt;
}

std::variant<RequestHead, HttpError> parse_request_head(std::string_view head) {
  // Tolerate leading empty lines before the request line (RFC 9112 section 2.2).
  while (head.starts_with("\r\n")) head.remove_prefix(2);

  const auto line_end = head.find("\r\n");
  const std::string_view request_line = head.substr(0, line_end);
  std::string_view rest = line_end == std::string_view::npos ? std::string_view{} : head.substr(line_end + 2);

  const auto sp1 = request_line.find(' ');
  const auto sp2 = sp1 == std::string_view::npos ? sp1 : request_line.find(' ', sp1 + 1);
  if (sp2 == std::string_view::npos || request_line.find(' ', sp2 + 1) != std::string_view::npos) {
    return bad_request("malformed request line");
  }

  RequestHead out;
  out.method = request_line.substr(0, sp1);
  out.target = request_line.substr(sp1 + 1, sp2 - sp1 - 1);
  out.version = request_line.substr(sp2 + 1);
  if (!is_token(out.method)) return bad_request("invalid method");
  if (out.target.empty() || out.target.front() != '/') return bad_request("invalid request target");
  if (out.version != "HTTP/1.1" && out.version != "HTTP/1.0") return HttpError{505, "unsupported HTTP version"};

  while (!rest.empty()) {
    const auto end = rest.find("\r\n");
    const std::string_view line = rest.substr(0, end);
    rest = end == std::string_view::npos ? std::string_view{} : rest.substr(end + 2);

    const auto colon = line.find(':');
    if (colon == std::string_view::npos) return bad_request("malformed header field");
    const std::string_view name = line.substr(0, colon);
    if (!is_token(name)) return bad_request("invalid header name");
    out.headers.emplace_back(name, trim_ows(line.substr(colon + 1)));
  }
  return out;
}

std::variant<std::size_t, HttpError> body_length(const RequestHead& head) {
  if (head.header("Transfer-Encoding")) return HttpError{501, "Transfer-Encoding is not supported"};

  std::optional<std::size_t> length;
  for (const auto& [key, value] : head.headers) {
    if (!iequals(key, "Content-Length")) continue;
    std::size_t parsed{};
    const auto [ptr, ec] = std::from_chars(value.data(), value.data() + value.size(), parsed);
    if (value.empty() || ec != std::errc{} || ptr != value.data() + value.size()) {
      return ec == std::errc::result_out_of_range ? HttpError{413, "body too large"} : bad_request("invalid Content-Length");
    }
    if (length && *length != parsed) return bad_request("conflicting Content-Length");
    length = parsed;
  }
  if (length.value_or(0) > kMaxBodyBytes) return HttpError{413, "body too large"};
  return length.value_or(0);
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
    case 408: return "Request Timeout";
    case 413: return "Content Too Large";
    case 431: return "Request Header Fields Too Large";
    case 500: return "Internal Server Error";
    case 501: return "Not Implemented";
    case 505: return "HTTP Version Not Supported";
    default: return "Unknown";
  }
}

std::string serialize(const Response& response) {
  std::string out;
  out.reserve(256 + response.body.size());
  auto sink = std::back_inserter(out);
  std::format_to(sink, "HTTP/1.1 {} {}\r\n", response.status, reason_phrase(response.status));
  if (!response.content_type.empty()) std::format_to(sink, "Content-Type: {}\r\n", response.content_type);
  for (const auto& [name, value] : response.extra_headers) std::format_to(sink, "{}: {}\r\n", name, value);
  // A 204 response has no body and must not carry Content-Length (RFC 9110 section 8.6).
  if (response.status != 204) std::format_to(sink, "Content-Length: {}\r\n", response.body.size());
  out += "Connection: close\r\n\r\n";
  if (response.status != 204) out += response.body;
  return out;
}

}  // namespace kvhttp
