#include "http.h"

#include <errno.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <sys/uio.h>
#include <unistd.h>

/* ---------- buffered reader over the bytes that followed the head ---------- */

typedef struct {
    int fd;
    size_t pos, len;
    unsigned char buf[HTTP_HEAD_MAX];
} reader;

/* Returns >0 bytes read, 0 on EOF, -1 on error/timeout. */
static ssize_t recv_some(int fd, void *buf, size_t cap)
{
    for (;;) {
        ssize_t n = recv(fd, buf, cap, 0);
        if (n >= 0 || errno != EINTR)
            return n;
    }
}

static int reader_fill(reader *r)
{
    if (r->pos < r->len)
        return 0;
    ssize_t n = recv_some(r->fd, r->buf, sizeof r->buf);
    if (n <= 0)
        return -1;
    r->pos = 0;
    r->len = (size_t)n;
    return 0;
}

static int reader_exact(reader *r, unsigned char *dst, size_t n)
{
    /* Drain buffered bytes first, then read large bodies straight into dst. */
    size_t avail = r->len - r->pos;
    size_t take = avail < n ? avail : n;
    memcpy(dst, r->buf + r->pos, take);
    r->pos += take;
    dst += take;
    n -= take;
    while (n > 0) {
        ssize_t got = recv_some(r->fd, dst, n);
        if (got <= 0)
            return -1;
        dst += got;
        n -= (size_t)got;
    }
    return 0;
}

/* Reads a line terminated by LF (CR stripped) into out, NUL-terminated.
 * Returns length, -1 on I/O failure, -2 if the line exceeds cap-1. */
static ssize_t reader_line(reader *r, char *out, size_t cap)
{
    size_t n = 0;
    for (;;) {
        if (reader_fill(r) != 0)
            return -1;
        unsigned char c = r->buf[r->pos++];
        if (c == '\n')
            break;
        if (n + 1 >= cap)
            return -2;
        out[n++] = (char)c;
    }
    if (n > 0 && out[n - 1] == '\r')
        n--;
    out[n] = '\0';
    return (ssize_t)n;
}

/* ---------- parsing helpers ---------- */

static bool is_tchar(unsigned char c)
{
    if ((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9'))
        return true;
    return c != '\0' && strchr("!#$%&'*+-.^_`|~", c) != NULL;
}

/* Parses a non-empty decimal number; returns false on garbage or overflow. */
static bool parse_size(const char *s, size_t *out)
{
    if (!*s)
        return false;
    uint64_t v = 0;
    for (; *s; s++) {
        if (*s < '0' || *s > '9')
            return false;
        if (v > (UINT64_MAX - 9) / 10)
            return false;
        v = v * 10 + (uint64_t)(*s - '0');
    }
    if (v > SIZE_MAX)
        return false;
    *out = (size_t)v;
    return true;
}

static char *trim(char *s)
{
    while (*s == ' ' || *s == '\t')
        s++;
    char *end = s + strlen(s);
    while (end > s && (end[-1] == ' ' || end[-1] == '\t'))
        *--end = '\0';
    return s;
}

/* Finds the end of the header block; returns offset past the blank line. */
static size_t find_head_end(const char *buf, size_t len)
{
    for (size_t i = 0; i + 1 < len; i++) {
        if (buf[i] != '\n')
            continue;
        if (buf[i + 1] == '\n')
            return i + 2;
        if (i + 2 < len && buf[i + 1] == '\r' && buf[i + 2] == '\n')
            return i + 3;
    }
    return 0;
}

/* Splits off the next line in place; returns NULL when exhausted. */
static char *next_line(char **cursor)
{
    char *s = *cursor;
    char *nl = strchr(s, '\n');
    if (!nl)
        return NULL;
    *nl = '\0';
    if (nl > s && nl[-1] == '\r')
        nl[-1] = '\0';
    *cursor = nl + 1;
    return s;
}

typedef struct {
    bool has_length;
    size_t length;
    bool chunked;
    bool expect_continue;
} body_info;

static int parse_head(http_request *req, body_info *bi)
{
    char *cursor = req->head;
    char *line = next_line(&cursor);
    if (!line)
        return 400;

    /* Request line: method SP target SP HTTP/1.x */
    char *sp1 = strchr(line, ' ');
    if (!sp1)
        return 400;
    *sp1 = '\0';
    char *target = sp1 + 1;
    char *sp2 = strchr(target, ' ');
    if (!sp2)
        return 400;
    *sp2 = '\0';
    const char *version = sp2 + 1;

    if (!*line || !*target)
        return 400;
    for (const char *p = line; *p; p++)
        if (!is_tchar((unsigned char)*p))
            return 400;
    if (strncmp(version, "HTTP/1.", 7) != 0 || version[7] < '0' || version[7] > '9' || version[8])
        return strncmp(version, "HTTP/", 5) == 0 ? 505 : 400;
    req->method = line;
    req->target = target;

    while ((line = next_line(&cursor)) != NULL && *line) {
        char *colon = strchr(line, ':');
        if (!colon || colon == line)
            return 400;
        *colon = '\0';
        for (const char *p = line; *p; p++)
            if (!is_tchar((unsigned char)*p))
                return 400;
        char *value = trim(colon + 1);

        if (strcasecmp(line, "Content-Length") == 0) {
            size_t n;
            if (!parse_size(value, &n))
                return 400;
            if (bi->has_length && bi->length != n)
                return 400;
            bi->has_length = true;
            bi->length = n;
        } else if (strcasecmp(line, "Transfer-Encoding") == 0) {
            if (strcasecmp(value, "chunked") != 0)
                return 501;
            bi->chunked = true;
        } else if (strcasecmp(line, "Expect") == 0) {
            if (strcasecmp(value, "100-continue") != 0)
                return 417;
            bi->expect_continue = true;
        }
    }
    if (bi->chunked && bi->has_length)
        return 400;
    return 0;
}

static int send_all(int fd, const void *buf, size_t len)
{
    const char *p = buf;
    while (len > 0) {
        ssize_t n = send(fd, p, len, 0);
        if (n < 0) {
            if (errno == EINTR)
                continue;
            return -1;
        }
        p += n;
        len -= (size_t)n;
    }
    return 0;
}

static int read_chunked(reader *r, http_request *req, size_t max_body)
{
    char line[256];
    size_t cap = 0;
    for (;;) {
        ssize_t n = reader_line(r, line, sizeof line);
        if (n == -1)
            return -1;
        if (n == -2)
            return 400;
        char *ext = strchr(line, ';');
        if (ext)
            *ext = '\0';
        char *hex = trim(line);
        if (!*hex)
            return 400;
        size_t size = 0;
        for (const char *p = hex; *p; p++) {
            int d;
            if (*p >= '0' && *p <= '9')
                d = *p - '0';
            else if (*p >= 'a' && *p <= 'f')
                d = *p - 'a' + 10;
            else if (*p >= 'A' && *p <= 'F')
                d = *p - 'A' + 10;
            else
                return 400;
            if (size > (SIZE_MAX >> 4))
                return 413;
            size = (size << 4) | (size_t)d;
        }
        if (size == 0)
            break;
        if (size > max_body - req->body_len)
            return 413;

        size_t need = req->body_len + size;
        if (need > cap) {
            size_t ncap = cap ? cap : 4096;
            while (ncap < need)
                ncap *= 2;
            if (ncap > max_body)
                ncap = max_body;
            unsigned char *nb = realloc(req->body, ncap);
            if (!nb)
                return 500;
            req->body = nb;
            cap = ncap;
        }
        if (reader_exact(r, req->body + req->body_len, size) != 0)
            return -1;
        req->body_len += size;

        n = reader_line(r, line, sizeof line);
        if (n == -1)
            return -1;
        if (n != 0)
            return 400;
    }
    /* Trailer section: skip until the blank line. */
    for (;;) {
        ssize_t n = reader_line(r, line, sizeof line);
        if (n == -1)
            return -1;
        if (n == 0)
            break;
    }
    return 0;
}

int http_read_request(int fd, http_request *req, size_t max_body)
{
    req->method = NULL;
    req->target = NULL;
    req->body = NULL;
    req->body_len = 0;

    size_t filled = 0, head_end = 0;
    while (!(head_end = find_head_end(req->head, filled))) {
        if (filled == HTTP_HEAD_MAX)
            return 431;
        ssize_t n = recv_some(fd, req->head + filled, HTTP_HEAD_MAX - filled);
        if (n <= 0)
            return -1;
        filled += (size_t)n;
        req->head[filled] = '\0';
    }

    reader *r = malloc(sizeof *r);
    if (!r)
        return 500;
    r->fd = fd;
    r->pos = 0;
    r->len = filled - head_end;
    memcpy(r->buf, req->head + head_end, r->len);
    req->head[head_end] = '\0';

    body_info bi = {0};
    int rc = parse_head(req, &bi);
    if (rc != 0)
        goto out;

    if (bi.has_length && bi.length > max_body) {
        rc = 413;
        goto out;
    }
    if (bi.expect_continue && (bi.chunked || bi.length > 0)) {
        static const char cont[] = "HTTP/1.1 100 Continue\r\n\r\n";
        if (send_all(fd, cont, sizeof cont - 1) != 0) {
            rc = -1;
            goto out;
        }
    }

    if (bi.chunked) {
        rc = read_chunked(r, req, max_body);
    } else if (bi.length > 0) {
        req->body = malloc(bi.length);
        if (!req->body) {
            rc = 500;
            goto out;
        }
        if (reader_exact(r, req->body, bi.length) != 0)
            rc = -1;
        else
            req->body_len = bi.length;
    }

out:
    free(r);
    return rc;
}

void http_request_cleanup(http_request *req)
{
    free(req->body);
    req->body = NULL;
    req->body_len = 0;
}

static const char *reason(int status)
{
    switch (status) {
    case 100: return "Continue";
    case 200: return "OK";
    case 201: return "Created";
    case 204: return "No Content";
    case 400: return "Bad Request";
    case 404: return "Not Found";
    case 405: return "Method Not Allowed";
    case 413: return "Content Too Large";
    case 417: return "Expectation Failed";
    case 431: return "Request Header Fields Too Large";
    case 500: return "Internal Server Error";
    case 501: return "Not Implemented";
    case 505: return "HTTP Version Not Supported";
    default: return "Unknown";
    }
}

int http_send(int fd, int status, const char *content_type, const void *body, size_t len)
{
    char head[256];
    int n;
    if (content_type)
        n = snprintf(head, sizeof head,
                     "HTTP/1.1 %d %s\r\nContent-Type: %s\r\nContent-Length: %zu\r\nConnection: close\r\n\r\n",
                     status, reason(status), content_type, len);
    else
        n = snprintf(head, sizeof head,
                     "HTTP/1.1 %d %s\r\nContent-Length: %zu\r\nConnection: close\r\n\r\n",
                     status, reason(status), len);
    if (n < 0 || (size_t)n >= sizeof head)
        return -1;

    /* Send head and body together to avoid an extra small packet. */
    struct iovec iov[2] = {
        {.iov_base = head, .iov_len = (size_t)n},
        {.iov_base = (void *)body, .iov_len = body ? len : 0},
    };
    int iovcnt = 2;
    struct iovec *v = iov;
    while (iovcnt > 0) {
        ssize_t w = writev(fd, v, iovcnt);
        if (w < 0) {
            if (errno == EINTR)
                continue;
            return -1;
        }
        size_t done = (size_t)w;
        while (iovcnt > 0 && done >= v->iov_len) {
            done -= v->iov_len;
            v++;
            iovcnt--;
        }
        if (iovcnt > 0) {
            v->iov_base = (char *)v->iov_base + done;
            v->iov_len -= done;
        }
    }
    return 0;
}
