#include "http.h"

#include <ctype.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>

size_t http_head_length(const char *buf, size_t len)
{
    /* Accept both CRLF CRLF and bare LF LF terminators. */
    for (size_t i = 0; i + 1 < len; i++) {
        if (buf[i] != '\n')
            continue;
        if (buf[i + 1] == '\n')
            return i + 2;
        if (buf[i + 1] == '\r' && i + 2 < len && buf[i + 2] == '\n')
            return i + 3;
    }
    return 0;
}

bool http_slice_eq(http_slice s, const char *lit)
{
    size_t n = strlen(lit);
    return s.len == n && memcmp(s.ptr, lit, n) == 0;
}

static bool slice_ieq(http_slice s, const char *lit)
{
    size_t n = strlen(lit);
    return s.len == n && strncasecmp(s.ptr, lit, n) == 0;
}

static http_slice trim(const char *p, const char *end)
{
    while (p < end && (*p == ' ' || *p == '\t'))
        p++;
    while (end > p && (end[-1] == ' ' || end[-1] == '\t' || end[-1] == '\r'))
        end--;
    return (http_slice){p, (size_t)(end - p)};
}

static bool is_tchar(unsigned char c)
{
    return isalnum(c) || (c && strchr("!#$%&'*+-.^_`|~", c));
}

/* Parses a Content-Length value: one or more digits, no sign, no overflow. */
static bool parse_length(http_slice v, size_t *out)
{
    if (v.len == 0)
        return false;
    size_t n = 0;
    for (size_t i = 0; i < v.len; i++) {
        unsigned char c = (unsigned char)v.ptr[i];
        if (!isdigit(c))
            return false;
        if (n > (SIZE_MAX - 9) / 10)
            return false;
        n = n * 10 + (size_t)(c - '0');
    }
    *out = n;
    return true;
}

static int parse_request_line(const char *p, const char *eol, http_request *req)
{
    const char *sp1 = memchr(p, ' ', (size_t)(eol - p));
    if (!sp1)
        return 400;
    const char *sp2 = memchr(sp1 + 1, ' ', (size_t)(eol - sp1 - 1));
    if (!sp2)
        return 400;

    req->method = (http_slice){p, (size_t)(sp1 - p)};
    req->target = (http_slice){sp1 + 1, (size_t)(sp2 - sp1 - 1)};
    http_slice version = trim(sp2 + 1, eol);

    if (req->method.len == 0 || req->target.len == 0)
        return 400;
    for (size_t i = 0; i < req->method.len; i++)
        if (!is_tchar((unsigned char)req->method.ptr[i]))
            return 400;
    if (version.len != 8 || memcmp(version.ptr, "HTTP/", 5) != 0 ||
        !isdigit((unsigned char)version.ptr[5]) || version.ptr[6] != '.' ||
        !isdigit((unsigned char)version.ptr[7]))
        return 400;
    if (version.ptr[5] != '1')
        return 505;
    return 0;
}

int http_parse_head(const char *buf, size_t head_len, http_request *req)
{
    const char *p = buf;
    const char *end = buf + head_len;

    memset(req, 0, sizeof *req);

    /* Tolerate leading empty lines (RFC 9112 section 2.2). */
    while (p < end && (*p == '\r' || *p == '\n'))
        p++;

    const char *eol = memchr(p, '\n', (size_t)(end - p));
    if (!eol)
        return 400;
    int rc = parse_request_line(p, eol, req);
    if (rc)
        return rc;

    bool have_length = false;
    for (p = eol + 1; p < end; p = eol + 1) {
        eol = memchr(p, '\n', (size_t)(end - p));
        if (!eol)
            return 400;
        http_slice line = trim(p, eol);
        if (line.len == 0)
            break; /* end of head */
        if (*p == ' ' || *p == '\t')
            return 400; /* obsolete line folding */

        const char *colon = memchr(line.ptr, ':', line.len);
        if (!colon || colon == line.ptr)
            return 400;
        http_slice name = {line.ptr, (size_t)(colon - line.ptr)};
        for (size_t i = 0; i < name.len; i++)
            if (!is_tchar((unsigned char)name.ptr[i]))
                return 400;
        http_slice value = trim(colon + 1, line.ptr + line.len);

        if (slice_ieq(name, "Content-Length")) {
            size_t n;
            if (!parse_length(value, &n))
                return 400;
            if (have_length && n != req->content_length)
                return 400;
            req->content_length = n;
            have_length = true;
        } else if (slice_ieq(name, "Transfer-Encoding")) {
            if (!slice_ieq(value, "identity"))
                return 501;
        } else if (slice_ieq(name, "Expect")) {
            if (slice_ieq(value, "100-continue"))
                req->expect_continue = true;
        }
    }
    return 0;
}

const char *http_reason(int status)
{
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
    case 503: return "Service Unavailable";
    case 505: return "HTTP Version Not Supported";
    default:  return "Unknown";
    }
}

char *http_build_response(int status, const char *content_type,
                          const void *body, size_t body_len, size_t *out_len)
{
    char head[256];
    int n;
    /* 204 must not carry a body or Content-Length. */
    if (status == 204)
        n = snprintf(head, sizeof head,
                     "HTTP/1.1 204 No Content\r\nConnection: close\r\n\r\n");
    else
        n = snprintf(head, sizeof head,
                     "HTTP/1.1 %d %s\r\n"
                     "%s%s%s"
                     "Content-Length: %zu\r\n"
                     "Connection: close\r\n\r\n",
                     status, http_reason(status),
                     content_type ? "Content-Type: " : "",
                     content_type ? content_type : "",
                     content_type ? "\r\n" : "",
                     body_len);
    if (n < 0 || (size_t)n >= sizeof head)
        return NULL;
    if (status == 204)
        body_len = 0;

    char *out = malloc((size_t)n + body_len);
    if (!out)
        return NULL;
    memcpy(out, head, (size_t)n);
    if (body_len)
        memcpy(out + n, body, body_len);
    *out_len = (size_t)n + body_len;
    return out;
}
