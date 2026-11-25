/* kvhttp: a small HTTP/1.1 in-memory key/value server.
 * One request per connection, one detached thread per connection. */
#define _DARWIN_C_SOURCE
#define _POSIX_C_SOURCE 200809L

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
#include <sys/uio.h>
#include <time.h>
#include <unistd.h>

#include "store.h"

enum {
    MAX_HEADER_BYTES = 16 * 1024,
    MAX_VALUE_BYTES = 1024 * 1024,
    MAX_KEY_LEN = 64,
    IO_TIMEOUT_SEC = 30,
    DRAIN_LIMIT_BYTES = 4 * 1024 * 1024,
    THREAD_STACK_BYTES = 256 * 1024,
};

static kv_store *g_store;

/* ---------- response helpers ---------- */

static const char *reason_phrase(int status)
{
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
    default:  return "Unknown";
    }
}

typedef struct {
    int status;
    const char *content_type; /* NULL for none */
    const char *allow;        /* Allow header for 405, else NULL */
    const void *body;
    size_t body_len;
    void *owned;              /* freed after sending */
} response;

static bool write_all_iov(int fd, struct iovec *iov, int iovcnt)
{
    while (iovcnt > 0) {
        ssize_t n = writev(fd, iov, iovcnt);
        if (n < 0) {
            if (errno == EINTR)
                continue;
            return false;
        }
        size_t left = (size_t)n;
        while (iovcnt > 0 && left >= iov->iov_len) {
            left -= iov->iov_len;
            iov++;
            iovcnt--;
        }
        if (iovcnt > 0) {
            iov->iov_base = (char *)iov->iov_base + left;
            iov->iov_len -= left;
        }
    }
    return true;
}

static void send_response(int fd, const response *r)
{
    char head[512];
    int w = snprintf(head, sizeof head,
                     "HTTP/1.1 %d %s\r\n"
                     "Content-Length: %zu\r\n"
                     "%s%s%s"
                     "%s%s%s"
                     "Connection: close\r\n"
                     "\r\n",
                     r->status, reason_phrase(r->status), r->body_len,
                     r->content_type ? "Content-Type: " : "",
                     r->content_type ? r->content_type : "",
                     r->content_type ? "\r\n" : "",
                     r->allow ? "Allow: " : "", r->allow ? r->allow : "",
                     r->allow ? "\r\n" : "");
    if (w < 0 || (size_t)w >= sizeof head)
        return;
    struct iovec iov[2] = {
        {.iov_base = head, .iov_len = (size_t)w},
        {.iov_base = (void *)(uintptr_t)r->body, .iov_len = r->body_len},
    };
    write_all_iov(fd, iov, r->body_len ? 2 : 1);
}

static response simple(int status)
{
    return (response){.status = status};
}

static response text(int status, const char *body)
{
    return (response){.status = status, .content_type = "text/plain; charset=utf-8",
                      .body = body, .body_len = strlen(body)};
}

static response method_not_allowed(const char *allow)
{
    response r = text(405, "method not allowed");
    r.allow = allow;
    return r;
}

/* ---------- request parsing ---------- */

typedef struct {
    const char *method;
    size_t method_len;
    const char *target;
    size_t target_len;
    size_t content_length;
    bool has_content_length;
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

static const char *find_crlf(const char *p, const char *end)
{
    for (; p + 1 < end; p++)
        if (p[0] == '\r' && p[1] == '\n')
            return p;
    return NULL;
}

static bool parse_size(const char *s, size_t len, size_t *out)
{
    if (len == 0)
        return false;
    size_t v = 0;
    for (size_t i = 0; i < len; i++) {
        if (s[i] < '0' || s[i] > '9')
            return false;
        if (__builtin_mul_overflow(v, 10, &v) ||
            __builtin_add_overflow(v, (size_t)(s[i] - '0'), &v))
            return false;
    }
    *out = v;
    return true;
}

/* Parses the request head in [buf, end) (ending just before the blank line).
 * Returns 0 or an HTTP status code to reply with. */
static int parse_head(const char *buf, const char *end, request *req)
{
    const char *line_end = find_crlf(buf, end + 2);
    if (!line_end)
        return 400;

    const char *sp1 = memchr(buf, ' ', (size_t)(line_end - buf));
    if (!sp1 || sp1 == buf)
        return 400;
    const char *sp2 = memchr(sp1 + 1, ' ', (size_t)(line_end - sp1 - 1));
    if (!sp2 || sp2 == sp1 + 1)
        return 400;
    req->method = buf;
    req->method_len = (size_t)(sp1 - buf);
    req->target = sp1 + 1;
    req->target_len = (size_t)(sp2 - sp1 - 1);
    const char *version = sp2 + 1;
    size_t version_len = (size_t)(line_end - version);
    if (version_len != 8 || memcmp(version, "HTTP/1.", 7) != 0)
        return version_len >= 5 && memcmp(version, "HTTP/", 5) == 0 ? 505 : 400;

    for (const char *p = line_end + 2; p < end;) {
        const char *eol = find_crlf(p, end + 2);
        if (!eol)
            return 400;
        const char *colon = memchr(p, ':', (size_t)(eol - p));
        if (!colon || colon == p)
            return 400;
        size_t name_len = (size_t)(colon - p);
        const char *v = colon + 1;
        const char *vend = eol;
        while (v < vend && (*v == ' ' || *v == '\t'))
            v++;
        while (vend > v && (vend[-1] == ' ' || vend[-1] == '\t'))
            vend--;
        size_t vlen = (size_t)(vend - v);

        if (token_ieq(p, name_len, "Content-Length")) {
            size_t n;
            if (!parse_size(v, vlen, &n))
                return 400;
            if (req->has_content_length && req->content_length != n)
                return 400;
            req->content_length = n;
            req->has_content_length = true;
        } else if (token_ieq(p, name_len, "Transfer-Encoding")) {
            req->chunked = true;
        } else if (token_ieq(p, name_len, "Expect")) {
            if (token_ieq(v, vlen, "100-continue"))
                req->expect_continue = true;
        }
        p = eol + 2;
    }
    return 0;
}

/* ---------- routing ---------- */

static bool valid_key(const char *k, size_t len)
{
    if (len == 0 || len > MAX_KEY_LEN)
        return false;
    for (size_t i = 0; i < len; i++) {
        unsigned char c = (unsigned char)k[i];
        bool ok = (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') ||
                  (c >= '0' && c <= '9') || c == '_' || c == '-';
        if (!ok)
            return false;
    }
    return true;
}

static response handle_key(const request *req, const char *key, size_t key_len,
                           char *body, size_t body_len, char **body_owner)
{
    if (!valid_key(key, key_len))
        return text(400, "invalid key");

    const char *m = req->method;
    size_t ml = req->method_len;

    if (token_eq(m, ml, "GET")) {
        void *val = NULL;
        size_t len = 0;
        int rc = kv_store_get(g_store, key, key_len, &val, &len);
        if (rc == ENOENT)
            return text(404, "not found");
        if (rc != 0)
            return text(500, "out of memory");
        return (response){.status = 200, .content_type = "application/octet-stream",
                          .body = val, .body_len = len, .owned = val};
    }
    if (token_eq(m, ml, "PUT")) {
        bool created = false;
        if (kv_store_put(g_store, key, key_len, body, body_len, &created) != 0)
            return text(500, "out of memory");
        *body_owner = NULL; /* the store owns it now */
        return simple(created ? 201 : 200);
    }
    if (token_eq(m, ml, "DELETE")) {
        if (kv_store_delete(g_store, key, key_len) != 0)
            return text(404, "not found");
        return simple(204);
    }
    return method_not_allowed("GET, PUT, DELETE");
}

static response route(const request *req, char *body, size_t body_len, char **body_owner)
{
    const char *path = req->target;
    size_t len = req->target_len;
    const char *m = req->method;
    size_t ml = req->method_len;

    if (token_eq(path, len, "/health")) {
        if (!token_eq(m, ml, "GET"))
            return method_not_allowed("GET");
        return text(200, "ok");
    }
    if (token_eq(path, len, "/kv")) {
        if (!token_eq(m, ml, "GET"))
            return method_not_allowed("GET");
        char *json = NULL;
        size_t jlen = 0;
        if (kv_store_keys_json(g_store, &json, &jlen) != 0)
            return text(500, "out of memory");
        return (response){.status = 200, .content_type = "application/json",
                          .body = json, .body_len = jlen, .owned = json};
    }
    static const char prefix[] = "/kv/";
    if (len >= sizeof prefix - 1 && memcmp(path, prefix, sizeof prefix - 1) == 0)
        return handle_key(req, path + sizeof prefix - 1, len - (sizeof prefix - 1),
                          body, body_len, body_owner);
    return text(404, "not found");
}

/* ---------- connection handling ---------- */

static ssize_t read_some(int fd, void *buf, size_t len)
{
    for (;;) {
        ssize_t n = read(fd, buf, len);
        if (n >= 0 || errno != EINTR)
            return n;
    }
}

/* Reads and discards input briefly so that closing the socket does not
 * reset the connection before the client has read our response. */
static void drain_and_close(int fd)
{
    shutdown(fd, SHUT_WR);
    struct timeval tv = {.tv_sec = 1};
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof tv);
    char sink[16384];
    size_t total = 0;
    while (total < DRAIN_LIMIT_BYTES) {
        ssize_t n = read_some(fd, sink, sizeof sink);
        if (n <= 0)
            break;
        total += (size_t)n;
    }
    close(fd);
}

static const char *find_head_end(const char *buf, size_t len)
{
    for (size_t i = 3; i < len; i++)
        if (buf[i] == '\n' && buf[i - 1] == '\r' && buf[i - 2] == '\n' && buf[i - 3] == '\r')
            return buf + i - 3;
    return NULL;
}

static void serve_connection(int fd)
{
    char head[MAX_HEADER_BYTES];
    size_t have = 0;
    const char *head_end = NULL;
    size_t scanned = 0;
    char *body = NULL;
    response resp;

    while (!head_end) {
        if (have == sizeof head) {
            resp = text(431, "request header too large");
            goto reply;
        }
        ssize_t n = read_some(fd, head + have, sizeof head - have);
        if (n == 0)
            goto out_close; /* client went away */
        if (n < 0) {
            if (errno == EAGAIN || errno == EWOULDBLOCK) {
                resp = text(408, "request timeout");
                goto reply;
            }
            goto out_close;
        }
        have += (size_t)n;
        head_end = find_head_end(head + (scanned > 3 ? scanned - 3 : 0),
                                 have - (scanned > 3 ? scanned - 3 : 0));
        scanned = have;
    }

    request req = {0};
    int status = parse_head(head, head_end, &req);
    if (status != 0) {
        resp = text(status, reason_phrase(status));
        goto reply;
    }
    if (req.chunked) {
        resp = text(501, "transfer-encoding not supported");
        goto reply;
    }
    if (req.content_length > MAX_VALUE_BYTES) {
        resp = text(413, "value too large");
        goto reply;
    }

    size_t body_len = req.content_length;
    const char *extra = head_end + 4;
    size_t extra_len = have - (size_t)(extra - head);
    if (extra_len > body_len)
        extra_len = body_len; /* ignore pipelined bytes */
    if (body_len > 0) {
        body = malloc(body_len);
        if (!body) {
            resp = text(500, "out of memory");
            goto reply;
        }
        memcpy(body, extra, extra_len);
        if (req.expect_continue && extra_len < body_len) {
            static const char cont[] = "HTTP/1.1 100 Continue\r\n\r\n";
            struct iovec iov = {.iov_base = (void *)(uintptr_t)cont, .iov_len = sizeof cont - 1};
            write_all_iov(fd, &iov, 1);
        }
        for (size_t got = extra_len; got < body_len;) {
            ssize_t n = read_some(fd, body + got, body_len - got);
            if (n == 0)
                goto out_close;
            if (n < 0) {
                if (errno == EAGAIN || errno == EWOULDBLOCK) {
                    resp = text(408, "request timeout");
                    goto reply;
                }
                goto out_close;
            }
            got += (size_t)n;
        }
    }

    resp = route(&req, body, body_len, &body);

reply:
    send_response(fd, &resp);
    free(resp.owned);
    free(body);
    drain_and_close(fd);
    return;

out_close:
    free(body);
    close(fd);
}

static void *connection_thread(void *arg)
{
    int fd = (int)(intptr_t)arg;
    serve_connection(fd);
    return NULL;
}

static void configure_client(int fd)
{
    struct timeval tv = {.tv_sec = IO_TIMEOUT_SEC};
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof tv);
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof tv);
    int one = 1;
    setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &one, sizeof one);
#ifdef SO_NOSIGPIPE
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof one);
#endif
}

static int listen_on(uint16_t port)
{
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) {
        perror("socket");
        return -1;
    }
    int one = 1;
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof one);
    struct sockaddr_in addr = {
        .sin_family = AF_INET,
        .sin_port = htons(port),
        .sin_addr.s_addr = htonl(INADDR_LOOPBACK),
    };
    if (bind(fd, (struct sockaddr *)&addr, sizeof addr) != 0) {
        perror("bind");
        close(fd);
        return -1;
    }
    if (listen(fd, SOMAXCONN) != 0) {
        perror("listen");
        close(fd);
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
        fputs("out of memory\n", stderr);
        return EXIT_FAILURE;
    }
    int lfd = listen_on(port);
    if (lfd < 0)
        return EXIT_FAILURE;

    pthread_attr_t attr;
    pthread_attr_init(&attr);
    pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_DETACHED);
    pthread_attr_setstacksize(&attr, THREAD_STACK_BYTES);

    for (;;) {
        int cfd = accept(lfd, NULL, NULL);
        if (cfd < 0) {
            if (errno == EINTR || errno == ECONNABORTED)
                continue;
            if (errno == EMFILE || errno == ENFILE || errno == ENOBUFS || errno == ENOMEM) {
                nanosleep(&(struct timespec){.tv_nsec = 10 * 1000 * 1000}, NULL);
                continue;
            }
            perror("accept");
            break;
        }
        configure_client(cfd);
        pthread_t tid;
        int rc = pthread_create(&tid, &attr, connection_thread, (void *)(intptr_t)cfd);
        if (rc != 0) {
            /* Out of threads: serve inline rather than dropping the client. */
            serve_connection(cfd);
        }
    }
    pthread_attr_destroy(&attr);
    close(lfd);
    kv_store_free(g_store);
    return EXIT_FAILURE;
}
