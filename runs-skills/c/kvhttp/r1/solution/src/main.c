/* kvhttp: an in-memory HTTP/1.1 key-value server.
 *
 * One detached thread per connection, one request per connection. The store
 * is a reader/writer-locked hash table of reference-counted values. */
#define _DARWIN_C_SOURCE
#define _POSIX_C_SOURCE 200809L

#include "kv_store.h"

#include <arpa/inet.h>
#include <errno.h>
#include <limits.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <pthread.h>
#include <signal.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <sys/types.h>
#include <sys/uio.h>
#include <time.h>
#include <unistd.h>

#define MAX_HEADER_BYTES (32u * 1024u)
#define MAX_BODY_BYTES (1024u * 1024u)
#define IO_TIMEOUT_SEC 10
#define DRAIN_TIMEOUT_MS 500

static kv_store *g_store;

/* ---------- growable byte buffer ---------- */

typedef struct {
    unsigned char *data;
    size_t len;
    size_t cap;
} buf_t;

static int buf_reserve(buf_t *b, size_t extra)
{
    if (extra <= b->cap - b->len)
        return 0;
    if (extra > SIZE_MAX - b->len)
        return ENOMEM;
    size_t need = b->len + extra;
    size_t ncap = b->cap ? b->cap : 256;
    while (ncap < need) {
        if (ncap > SIZE_MAX / 2)
            return ENOMEM;
        ncap *= 2;
    }
    unsigned char *p = realloc(b->data, ncap);
    if (!p)
        return ENOMEM;
    b->data = p;
    b->cap = ncap;
    return 0;
}

static int buf_append(buf_t *b, const void *src, size_t n)
{
    int rc = buf_reserve(b, n);
    if (rc)
        return rc;
    if (n)
        memcpy(b->data + b->len, src, n);
    b->len += n;
    return 0;
}

static void buf_free(buf_t *b)
{
    free(b->data);
    *b = (buf_t){0};
}

/* ---------- socket I/O ---------- */

/* Reads more bytes into b. Returns bytes read, 0 on EOF, -1 on error/timeout. */
static ssize_t read_more(int fd, buf_t *b, size_t want)
{
    if (buf_reserve(b, want))
        return -1;
    for (;;) {
        ssize_t n = recv(fd, b->data + b->len, want, 0);
        if (n < 0 && errno == EINTR)
            continue;
        if (n > 0)
            b->len += (size_t)n;
        return n;
    }
}

static int write_all(int fd, struct iovec *iov, int iovcnt)
{
    while (iovcnt > 0) {
        ssize_t n = writev(fd, iov, iovcnt);
        if (n < 0) {
            if (errno == EINTR)
                continue;
            return -1;
        }
        size_t done = (size_t)n;
        while (iovcnt > 0 && done >= iov->iov_len) {
            done -= iov->iov_len;
            iov++;
            iovcnt--;
        }
        if (iovcnt > 0) {
            iov->iov_base = (char *)iov->iov_base + done;
            iov->iov_len -= done;
        }
    }
    return 0;
}

static void set_timeout(int fd, int opt, long ms)
{
    struct timeval tv = {.tv_sec = ms / 1000, .tv_usec = (int)(ms % 1000) * 1000};
    setsockopt(fd, SOL_SOCKET, opt, &tv, sizeof tv);
}

/* ---------- responses ---------- */

static const char *status_text(int status)
{
    switch (status) {
    case 200: return "OK";
    case 201: return "Created";
    case 204: return "No Content";
    case 400: return "Bad Request";
    case 404: return "Not Found";
    case 405: return "Method Not Allowed";
    case 411: return "Length Required";
    case 413: return "Content Too Large";
    case 431: return "Request Header Fields Too Large";
    case 500: return "Internal Server Error";
    case 501: return "Not Implemented";
    case 505: return "HTTP Version Not Supported";
    default: return "Unknown";
    }
}

typedef struct {
    int status;
    const char *content_type; /* NULL for none */
    const char *allow;        /* NULL unless 405 */
    const void *body;
    size_t body_len;
} response;

static void send_response(int fd, const response *r)
{
    char head[512];
    int n = snprintf(head, sizeof head, "HTTP/1.1 %d %s\r\nConnection: close\r\n",
                     r->status, status_text(r->status));
    size_t len = (size_t)n;
    /* RFC 9110: no Content-Length on 204. */
    if (r->status != 204)
        len += (size_t)snprintf(head + len, sizeof head - len, "Content-Length: %zu\r\n", r->body_len);
    if (r->content_type)
        len += (size_t)snprintf(head + len, sizeof head - len, "Content-Type: %s\r\n", r->content_type);
    if (r->allow)
        len += (size_t)snprintf(head + len, sizeof head - len, "Allow: %s\r\n", r->allow);
    len += (size_t)snprintf(head + len, sizeof head - len, "\r\n");

    struct iovec iov[2] = {
        {.iov_base = head, .iov_len = len},
        {.iov_base = (void *)(uintptr_t)r->body, .iov_len = r->body_len},
    };
    (void)write_all(fd, iov, r->body_len ? 2 : 1);
}

static void send_status(int fd, int status)
{
    response r = {.status = status};
    send_response(fd, &r);
}

static void send_text(int fd, int status, const char *text)
{
    response r = {.status = status, .content_type = "text/plain; charset=utf-8",
                  .body = text, .body_len = strlen(text)};
    send_response(fd, &r);
}

static void send_405(int fd, const char *allow)
{
    response r = {.status = 405, .allow = allow};
    send_response(fd, &r);
}

/* ---------- request parsing ---------- */

typedef struct {
    const char *method;
    size_t method_len;
    const char *path;
    size_t path_len;
    bool has_length;
    size_t content_length;
    bool chunked;
    bool expect_continue;
} request;

static bool token_eq(const char *s, size_t len, const char *lit)
{
    return strlen(lit) == len && memcmp(s, lit, len) == 0;
}

static bool token_ieq(const char *s, size_t len, const char *lit)
{
    return strlen(lit) == len && strncasecmp(s, lit, len) == 0;
}

static void trim_ows(const char **s, size_t *len)
{
    while (*len && (**s == ' ' || **s == '\t')) {
        (*s)++;
        (*len)--;
    }
    while (*len && ((*s)[*len - 1] == ' ' || (*s)[*len - 1] == '\t'))
        (*len)--;
}

/* Parses a non-negative decimal; returns false on syntax error or overflow. */
static bool parse_size(const char *s, size_t len, size_t *out)
{
    if (len == 0)
        return false;
    size_t v = 0;
    for (size_t i = 0; i < len; i++) {
        if (s[i] < '0' || s[i] > '9')
            return false;
        if (__builtin_mul_overflow(v, 10, &v) || __builtin_add_overflow(v, (size_t)(s[i] - '0'), &v))
            return false;
    }
    *out = v;
    return true;
}

/* Finds the end of the header block. Returns the offset just past the blank
 * line, or 0 if not yet complete. Accepts bare LF line endings. */
static size_t find_header_end(const unsigned char *p, size_t len)
{
    for (size_t i = 0; i + 1 < len; i++) {
        if (p[i] != '\n')
            continue;
        if (p[i + 1] == '\n')
            return i + 2;
        if (p[i + 1] == '\r' && i + 2 < len && p[i + 2] == '\n')
            return i + 3;
    }
    return 0;
}

/* Returns 0 on success or an HTTP status code describing the failure. */
static int parse_request(char *head, size_t len, request *req)
{
    *req = (request){0};
    char *end = head + len;
    char *eol = memchr(head, '\n', len);
    if (!eol)
        return 400;
    char *line_end = (eol > head && eol[-1] == '\r') ? eol - 1 : eol;

    /* Request line: method SP target SP version */
    char *sp1 = memchr(head, ' ', (size_t)(line_end - head));
    if (!sp1 || sp1 == head)
        return 400;
    char *target = sp1 + 1;
    char *sp2 = memchr(target, ' ', (size_t)(line_end - target));
    if (!sp2 || sp2 == target)
        return 400;
    char *version = sp2 + 1;
    size_t vlen = (size_t)(line_end - version);
    if (vlen != 8 || memcmp(version, "HTTP/1.", 7) != 0)
        return (vlen >= 5 && memcmp(version, "HTTP/", 5) == 0) ? 505 : 400;

    req->method = head;
    req->method_len = (size_t)(sp1 - head);
    req->path = target;
    req->path_len = (size_t)(sp2 - target);

    /* Strip a query string or fragment if a client sends one anyway. */
    const char *q = memchr(req->path, '?', req->path_len);
    if (q)
        req->path_len = (size_t)(q - req->path);

    for (char *line = eol + 1; line < end;) {
        char *nl = memchr(line, '\n', (size_t)(end - line));
        if (!nl)
            break;
        char *le = (nl > line && nl[-1] == '\r') ? nl - 1 : nl;
        if (le == line)
            break; /* blank line: end of headers */
        if (*line == ' ' || *line == '\t')
            return 400; /* obsolete line folding */
        char *colon = memchr(line, ':', (size_t)(le - line));
        if (!colon || colon == line)
            return 400;
        const char *name = line;
        size_t nlen = (size_t)(colon - line);
        const char *val = colon + 1;
        size_t vl = (size_t)(le - val);
        trim_ows(&val, &vl);

        if (token_ieq(name, nlen, "Content-Length")) {
            size_t cl;
            if (!parse_size(val, vl, &cl))
                return 400;
            if (req->has_length && cl != req->content_length)
                return 400;
            req->has_length = true;
            req->content_length = cl;
        } else if (token_ieq(name, nlen, "Transfer-Encoding")) {
            if (!token_ieq(val, vl, "chunked"))
                return 501;
            req->chunked = true;
        } else if (token_ieq(name, nlen, "Expect")) {
            if (token_ieq(val, vl, "100-continue"))
                req->expect_continue = true;
        }
        line = nl + 1;
    }
    if (req->chunked && req->has_length)
        return 400;
    return 0;
}

/* ---------- body reading ---------- */

/* Reads exactly n body bytes into body, using already-buffered bytes first.
 * Returns 0 or -1 on I/O failure. */
static int read_fixed_body(int fd, buf_t *in, size_t off, size_t n, buf_t *body)
{
    size_t have = in->len - off;
    if (have > n)
        have = n;
    if (buf_reserve(body, n) || buf_append(body, in->data + off, have))
        return -1;
    while (body->len < n) {
        ssize_t r = read_more(fd, body, n - body->len);
        if (r <= 0)
            return -1;
    }
    return 0;
}

/* Ensures at least `need` bytes are available in `in` past `off`. */
static int fill(int fd, buf_t *in, size_t off, size_t need)
{
    while (in->len - off < need) {
        ssize_t r = read_more(fd, in, 16384);
        if (r <= 0)
            return -1;
    }
    return 0;
}

/* Reads a line (without the CRLF) starting at *off. */
static int read_line(int fd, buf_t *in, size_t *off, const char **line, size_t *len)
{
    for (;;) {
        unsigned char *start = in->data + *off;
        unsigned char *nl = memchr(start, '\n', in->len - *off);
        if (nl) {
            size_t l = (size_t)(nl - start);
            *line = (const char *)start;
            *len = (l && start[l - 1] == '\r') ? l - 1 : l;
            *off += l + 1;
            return 0;
        }
        if (in->len - *off > 4096)
            return 400;
        if (fill(fd, in, *off, in->len - *off + 1))
            return -1;
    }
}

/* Decodes a chunked body. Returns 0, -1 on I/O error, or an HTTP status. */
static int read_chunked_body(int fd, buf_t *in, size_t off, buf_t *body)
{
    for (;;) {
        const char *line;
        size_t len;
        int rc = read_line(fd, in, &off, &line, &len);
        if (rc)
            return rc;
        const char *semi = memchr(line, ';', len);
        if (semi)
            len = (size_t)(semi - line);
        trim_ows(&line, &len);
        if (len == 0 || len > 8)
            return 400;
        size_t size = 0;
        for (size_t i = 0; i < len; i++) {
            int c = (unsigned char)line[i], d;
            if (c >= '0' && c <= '9') d = c - '0';
            else if (c >= 'a' && c <= 'f') d = c - 'a' + 10;
            else if (c >= 'A' && c <= 'F') d = c - 'A' + 10;
            else return 400;
            size = size * 16 + (size_t)d;
        }
        if (size == 0)
            break;
        if (size > MAX_BODY_BYTES - body->len)
            return 413;
        if (fill(fd, in, off, size) || buf_append(body, in->data + off, size))
            return -1;
        off += size;
        if ((rc = read_line(fd, in, &off, &line, &len)))
            return rc;
        if (len != 0)
            return 400;
    }
    /* Trailer section, terminated by an empty line. */
    for (;;) {
        const char *line;
        size_t len;
        int rc = read_line(fd, in, &off, &line, &len);
        if (rc)
            return rc;
        if (len == 0)
            return 0;
    }
}

/* ---------- routing ---------- */

static void handle_list(int fd)
{
    char **keys = NULL;
    size_t n = 0;
    if (kv_store_keys(g_store, &keys, &n)) {
        send_status(fd, 500);
        return;
    }
    buf_t out = {0};
    int rc = buf_append(&out, "[", 1);
    for (size_t i = 0; i < n && !rc; i++) {
        /* Keys are restricted to [A-Za-z0-9_-], so no JSON escaping is needed. */
        if (i)
            rc = buf_append(&out, ",", 1);
        if (!rc) rc = buf_append(&out, "\"", 1);
        if (!rc) rc = buf_append(&out, keys[i], strlen(keys[i]));
        if (!rc) rc = buf_append(&out, "\"", 1);
    }
    if (!rc)
        rc = buf_append(&out, "]", 1);
    kv_keys_free(keys, n);

    if (rc) {
        send_status(fd, 500);
    } else {
        response r = {.status = 200, .content_type = "application/json",
                      .body = out.data, .body_len = out.len};
        send_response(fd, &r);
    }
    buf_free(&out);
}

static void handle_get(int fd, const char *key, size_t klen)
{
    kv_value *v = kv_store_get(g_store, key, klen);
    if (!v) {
        send_status(fd, 404);
        return;
    }
    response r = {.status = 200, .content_type = "application/octet-stream",
                  .body = kv_value_data(v), .body_len = kv_value_len(v)};
    send_response(fd, &r);
    kv_value_release(v);
}

static void handle_put(int fd, const char *key, size_t klen, const buf_t *body)
{
    kv_value *v = kv_value_new(body->data, body->len);
    bool created = false;
    if (!v || kv_store_put(g_store, key, klen, v, &created)) {
        kv_value_release(v);
        send_status(fd, 500);
        return;
    }
    send_status(fd, created ? 201 : 200);
}

static void handle_delete(int fd, const char *key, size_t klen)
{
    send_status(fd, kv_store_delete(g_store, key, klen) ? 204 : 404);
}

typedef enum { ROUTE_NONE, ROUTE_HEALTH, ROUTE_LIST, ROUTE_KEY, ROUTE_BAD_KEY } route_kind;

static route_kind classify(const request *req, const char **key, size_t *klen)
{
    static const char prefix[] = "/kv/";
    const size_t plen = sizeof prefix - 1;
    if (token_eq(req->path, req->path_len, "/health"))
        return ROUTE_HEALTH;
    if (token_eq(req->path, req->path_len, "/kv"))
        return ROUTE_LIST;
    if (req->path_len >= plen && memcmp(req->path, prefix, plen) == 0) {
        *key = req->path + plen;
        *klen = req->path_len - plen;
        return kv_key_valid(*key, *klen) ? ROUTE_KEY : ROUTE_BAD_KEY;
    }
    return ROUTE_NONE;
}

/* ---------- connection handling ---------- */

/* Half-close and drain so the client sees the response rather than a reset
 * caused by unread request bytes. */
static void lingering_close(int fd)
{
    shutdown(fd, SHUT_WR);
    set_timeout(fd, SO_RCVTIMEO, DRAIN_TIMEOUT_MS);
    char sink[4096];
    struct timespec t0, t;
    clock_gettime(CLOCK_MONOTONIC, &t0);
    for (;;) {
        ssize_t n = recv(fd, sink, sizeof sink, 0);
        if (n == 0 || (n < 0 && errno != EINTR))
            break;
        clock_gettime(CLOCK_MONOTONIC, &t);
        long ms = (t.tv_sec - t0.tv_sec) * 1000L + (t.tv_nsec - t0.tv_nsec) / 1000000L;
        if (ms > DRAIN_TIMEOUT_MS)
            break;
    }
    close(fd);
}

static void serve(int fd)
{
    buf_t in = {0}, body = {0};
    size_t head_len = 0;

    while (!(head_len = find_header_end(in.data, in.len))) {
        if (in.len >= MAX_HEADER_BYTES) {
            send_status(fd, 431);
            goto out;
        }
        if (read_more(fd, &in, 4096) <= 0)
            goto out; /* client went away or timed out */
    }

    request req;
    int st = parse_request((char *)in.data, head_len, &req);
    if (st) {
        send_status(fd, st);
        goto out;
    }

    const char *path_key = NULL;
    size_t klen = 0;
    route_kind route = classify(&req, &path_key, &klen);
    bool is_get = token_eq(req.method, req.method_len, "GET");
    bool is_put = token_eq(req.method, req.method_len, "PUT");
    bool is_delete = token_eq(req.method, req.method_len, "DELETE");

    /* `req` points into `in`, which reading a chunked body may reallocate;
     * keep a private copy of the key. */
    char key[KV_KEY_MAX + 1] = {0};
    if (route == ROUTE_KEY)
        memcpy(key, path_key, klen);

    /* Only PUT /kv/<key> needs the body; everything else is answered now and
     * any body is drained by lingering_close. */
    switch (route) {
    case ROUTE_NONE:
        send_status(fd, 404);
        goto out;
    case ROUTE_BAD_KEY:
        send_status(fd, 400);
        goto out;
    case ROUTE_HEALTH:
        if (is_get)
            send_text(fd, 200, "ok");
        else
            send_405(fd, "GET");
        goto out;
    case ROUTE_LIST:
        if (is_get)
            handle_list(fd);
        else
            send_405(fd, "GET");
        goto out;
    case ROUTE_KEY:
        break;
    }

    if (is_get) {
        handle_get(fd, key, klen);
        goto out;
    }
    if (is_delete) {
        handle_delete(fd, key, klen);
        goto out;
    }
    if (!is_put) {
        send_405(fd, "GET, PUT, DELETE");
        goto out;
    }

    if (req.has_length && req.content_length > MAX_BODY_BYTES) {
        send_status(fd, 413);
        goto out;
    }
    if (req.expect_continue) {
        static const char cont[] = "HTTP/1.1 100 Continue\r\n\r\n";
        struct iovec iov = {.iov_base = (void *)(uintptr_t)cont, .iov_len = sizeof cont - 1};
        if (write_all(fd, &iov, 1))
            goto out;
    }
    if (req.chunked) {
        int rc = read_chunked_body(fd, &in, head_len, &body);
        if (rc) {
            if (rc > 0)
                send_status(fd, rc);
            goto out;
        }
    } else if (req.has_length) {
        if (read_fixed_body(fd, &in, head_len, req.content_length, &body))
            goto out;
    }
    handle_put(fd, key, klen, &body);

out:
    buf_free(&in);
    buf_free(&body);
    lingering_close(fd);
}

static void *conn_thread(void *arg)
{
    int fd = (int)(intptr_t)arg;
    serve(fd);
    return NULL;
}

static int listen_on(uint16_t port)
{
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0)
        return -1;
    int one = 1;
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof one);
    struct sockaddr_in addr = {
        .sin_family = AF_INET,
        .sin_port = htons(port),
        .sin_addr.s_addr = htonl(INADDR_LOOPBACK),
    };
    if (bind(fd, (struct sockaddr *)&addr, sizeof addr) < 0 || listen(fd, SOMAXCONN) < 0) {
        int e = errno;
        close(fd);
        errno = e;
        return -1;
    }
    return fd;
}

static bool parse_port(const char *s, uint16_t *out)
{
    char *end;
    errno = 0;
    long v = strtol(s, &end, 10);
    if (end == s || *end != '\0' || errno == ERANGE || v < 1 || v > 65535)
        return false;
    *out = (uint16_t)v;
    return true;
}

int main(int argc, char **argv)
{
    uint16_t port;
    if (argc != 2 || !parse_port(argv[1], &port)) {
        fprintf(stderr, "usage: %s <port>\n", argc > 0 ? argv[0] : "app");
        return EXIT_FAILURE;
    }
    signal(SIGPIPE, SIG_IGN);

    g_store = kv_store_new();
    if (!g_store) {
        fprintf(stderr, "out of memory\n");
        return EXIT_FAILURE;
    }
    int lfd = listen_on(port);
    if (lfd < 0) {
        perror("listen");
        return EXIT_FAILURE;
    }

    pthread_attr_t attr;
    pthread_attr_init(&attr);
    pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_DETACHED);

    for (;;) {
        int fd = accept(lfd, NULL, NULL);
        if (fd < 0) {
            if (errno == EINTR || errno == ECONNABORTED)
                continue;
            if (errno == EMFILE || errno == ENFILE || errno == ENOBUFS || errno == ENOMEM) {
                struct timespec ts = {.tv_sec = 0, .tv_nsec = 10 * 1000 * 1000};
                nanosleep(&ts, NULL);
                continue;
            }
            perror("accept");
            break;
        }
        int one = 1;
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof one);
        setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &one, sizeof one);
        set_timeout(fd, SO_RCVTIMEO, IO_TIMEOUT_SEC * 1000L);
        set_timeout(fd, SO_SNDTIMEO, IO_TIMEOUT_SEC * 1000L);

        pthread_t tid;
        if (pthread_create(&tid, &attr, conn_thread, (void *)(intptr_t)fd) != 0) {
            send_status(fd, 500);
            close(fd);
        }
    }

    pthread_attr_destroy(&attr);
    close(lfd);
    kv_store_free(g_store);
    return EXIT_FAILURE;
}
