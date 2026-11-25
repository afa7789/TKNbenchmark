#define _DARWIN_C_SOURCE
#define _POSIX_C_SOURCE 200809L

#include "http.h"

#include <errno.h>
#include <poll.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <sys/uio.h>
#include <time.h>
#include <unistd.h>

static ssize_t recv_some(int fd, void *buf, size_t len)
{
    for (;;) {
        ssize_t n = recv(fd, buf, len, 0);
        if (n >= 0 || errno != EINTR)
            return n;
    }
}

/* Locate "\r\n\r\n" in buf[0..len), scanning from `from`. Returns the offset
 * just past the terminator, or 0 if not present. */
static size_t find_header_end(const char *buf, size_t len, size_t from)
{
    for (size_t i = from; i + 4 <= len; i++) {
        if (buf[i] == '\r' && buf[i + 1] == '\n' && buf[i + 2] == '\r' && buf[i + 3] == '\n')
            return i + 4;
    }
    return 0;
}

static bool is_tchar(unsigned char c)
{
    if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9'))
        return true;
    return c != '\0' && strchr("!#$%&'*+-.^_`|~", c) != NULL;
}

static char *trim_ows(char *s, char *end)
{
    while (s < end && (*s == ' ' || *s == '\t'))
        s++;
    while (end > s && (end[-1] == ' ' || end[-1] == '\t'))
        end--;
    *end = '\0';
    return s;
}

/* Strict decimal parse; rejects signs, spaces and overflow. */
static bool parse_content_length(const char *s, size_t *out)
{
    if (*s == '\0')
        return false;
    size_t v = 0;
    for (; *s; s++) {
        if (*s < '0' || *s > '9')
            return false;
        if (__builtin_mul_overflow(v, 10, &v) ||
            __builtin_add_overflow(v, (size_t)(*s - '0'), &v))
            return false;
    }
    *out = v;
    return true;
}

/* Parse the request line and headers in place (buf is NUL-terminated at the
 * end of the header block). Returns 0 or an HTTP error status. */
static int parse_head(char *buf, http_request *req, bool *has_length)
{
    char *line_end = strstr(buf, "\r\n");
    if (!line_end)
        return 400;
    *line_end = '\0';

    /* request-line = method SP request-target SP HTTP-version */
    char *sp1 = strchr(buf, ' ');
    if (!sp1 || sp1 == buf)
        return 400;
    *sp1 = '\0';
    for (const char *p = buf; *p; p++)
        if (!is_tchar((unsigned char)*p))
            return 400;
    char *target = sp1 + 1;
    char *sp2 = strchr(target, ' ');
    if (!sp2 || sp2 == target)
        return 400;
    *sp2 = '\0';
    const char *version = sp2 + 1;
    if (strncmp(version, "HTTP/1.", 7) != 0 || version[7] < '0' || version[7] > '9' ||
        version[8] != '\0')
        return strncmp(version, "HTTP/", 5) == 0 ? 505 : 400;
    if (target[0] != '/')
        return 400;

    /* Paths in this API never carry queries, but ignore one defensively. */
    char *query = strchr(target, '?');
    if (query)
        *query = '\0';
    req->method = buf;
    req->path = target;
    req->path_len = strlen(target);

    *has_length = false;
    char *line = line_end + 2;
    while (*line != '\0') {
        char *eol = strstr(line, "\r\n");
        if (!eol)
            return 400;
        if (eol == line)
            break; /* blank line terminating the header block */
        char *colon = memchr(line, ':', (size_t)(eol - line));
        if (!colon || colon == line)
            return 400;
        for (const char *p = line; p < colon; p++)
            if (!is_tchar((unsigned char)*p))
                return 400;
        *colon = '\0';
        char *value = trim_ows(colon + 1, eol);

        if (strcasecmp(line, "Content-Length") == 0) {
            size_t len;
            if (!parse_content_length(value, &len))
                return 400;
            if (*has_length && len != req->content_length)
                return 400;
            req->content_length = len;
            *has_length = true;
        } else if (strcasecmp(line, "Transfer-Encoding") == 0) {
            return 501; /* chunked uploads are not supported */
        }
        line = eol + 2;
    }
    return 0;
}

int http_read_request(int fd, http_request *req)
{
    *req = (http_request){0};

    char *buf = malloc(HTTP_MAX_HEADER + 1);
    if (!buf)
        return 500;
    req->header_buf_ = buf;

    size_t len = 0, head_end = 0;
    while (head_end == 0) {
        if (len == HTTP_MAX_HEADER)
            return 431;
        ssize_t n = recv_some(fd, buf + len, HTTP_MAX_HEADER - len);
        if (n <= 0)
            return len == 0 ? -1 : (n == 0 ? 400 : -1);
        size_t from = len >= 3 ? len - 3 : 0;
        len += (size_t)n;
        head_end = find_header_end(buf, len, from);
    }

    /* Keep the body prefix aside before NUL-terminating the head. */
    size_t prefix_len = len - head_end;
    char saved = buf[head_end];
    buf[head_end] = '\0';

    bool has_length;
    int status = parse_head(buf, req, &has_length);
    if (status != 0)
        return status;
    if (!has_length || req->content_length == 0)
        return 0;
    if (req->content_length > HTTP_MAX_BODY) {
        req->body_too_large = true;
        return 0;
    }

    uint8_t *body = malloc(req->content_length);
    if (!body)
        return 500;
    req->body = body;

    buf[head_end] = saved;
    size_t have = prefix_len < req->content_length ? prefix_len : req->content_length;
    memcpy(body, buf + head_end, have);
    while (have < req->content_length) {
        ssize_t n = recv_some(fd, body + have, req->content_length - have);
        if (n <= 0)
            return n == 0 ? 400 : -1;
        have += (size_t)n;
    }
    req->body_len = have;
    return 0;
}

void http_request_free(http_request *req)
{
    free(req->body);
    free(req->header_buf_);
    *req = (http_request){0};
}

static const char *reason_phrase(int status)
{
    switch (status) {
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
    default:  return "Unknown";
    }
}

int http_send_response(int fd, int status, const char *extra_headers,
                       const void *body, size_t body_len)
{
    char head[512];
    int w = snprintf(head, sizeof head,
                     "HTTP/1.1 %d %s\r\n"
                     "Content-Length: %zu\r\n"
                     "Connection: close\r\n"
                     "%s"
                     "\r\n",
                     status, reason_phrase(status), body_len,
                     extra_headers ? extra_headers : "");
    if (w < 0 || (size_t)w >= sizeof head)
        return -1;

    struct iovec iov[2] = {
        {.iov_base = head, .iov_len = (size_t)w},
        {.iov_base = (void *)(uintptr_t)body, .iov_len = body ? body_len : 0},
    };
    int iovcnt = iov[1].iov_len ? 2 : 1;
    struct iovec *cur = iov;

    while (iovcnt > 0) {
        ssize_t n = writev(fd, cur, iovcnt);
        if (n < 0) {
            if (errno == EINTR)
                continue;
            return -1;
        }
        size_t done = (size_t)n;
        while (iovcnt > 0 && done >= cur->iov_len) {
            done -= cur->iov_len;
            cur++;
            iovcnt--;
        }
        if (iovcnt > 0) {
            cur->iov_base = (char *)cur->iov_base + done;
            cur->iov_len -= done;
        }
    }
    return 0;
}

static int64_t now_ms(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (int64_t)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

void http_close_gracefully(int fd)
{
    enum { LINGER_MS = 2000, LINGER_MAX_BYTES = 8 * 1024 * 1024 };

    if (shutdown(fd, SHUT_WR) == 0) {
        char sink[16384];
        size_t total = 0;
        int64_t deadline = now_ms() + LINGER_MS;
        while (total < LINGER_MAX_BYTES) {
            int64_t left = deadline - now_ms();
            if (left <= 0)
                break;
            struct pollfd pfd = {.fd = fd, .events = POLLIN};
            int r = poll(&pfd, 1, (int)left);
            if (r < 0 && errno == EINTR)
                continue;
            if (r <= 0)
                break;
            ssize_t n = recv_some(fd, sink, sizeof sink);
            if (n <= 0)
                break;
            total += (size_t)n;
        }
    }
    close(fd);
}
