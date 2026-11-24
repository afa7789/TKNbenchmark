/*
 * kvhttp: a minimal HTTP/1.1 in-memory key-value server.
 *
 * One detached thread per connection, one request per connection. The store
 * is guarded by a reader-writer lock (see store.c).
 */
#include "store.h"

#include <arpa/inet.h>
#include <errno.h>
#include <limits.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <pthread.h>
#include <signal.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <sys/uio.h>
#include <unistd.h>

enum {
    MAX_HEADER_BYTES = 16 * 1024,
    MAX_KEY_LEN = 64,
    IO_TIMEOUT_SEC = 10,
    DRAIN_LIMIT = 4 * 1024 * 1024,
};

#define MAX_VALUE_BYTES ((size_t)1 << 20)

static kv_store *g_store;

/* ------------------------------------------------------------------------ */
/* I/O helpers                                                              */

static bool write_all(int fd, struct iovec *iov, int iovcnt)
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

static ssize_t read_some(int fd, void *buf, size_t len)
{
    for (;;) {
        ssize_t n = read(fd, buf, len);
        if (n < 0 && errno == EINTR)
            continue;
        return n;
    }
}

/* Reads exactly len bytes; returns false on EOF, error or timeout. */
static bool read_exact(int fd, unsigned char *buf, size_t len)
{
    while (len > 0) {
        ssize_t n = read_some(fd, buf, len);
        if (n <= 0)
            return false;
        buf += n;
        len -= (size_t)n;
    }
    return true;
}

/* Half-close and drain whatever the peer still sends, so that closing the
 * socket does not reset the connection before the client reads the reply. */
static void lingering_close(int fd)
{
    char sink[4096];
    size_t total = 0;

    shutdown(fd, SHUT_WR);
    while (total < DRAIN_LIMIT) {
        ssize_t n = read_some(fd, sink, sizeof sink);
        if (n <= 0)
            break;
        total += (size_t)n;
    }
    close(fd);
}

/* ------------------------------------------------------------------------ */
/* Responses                                                                */

static const char *status_text(int status)
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
    const char *allow;        /* NULL for none; set on 405 */
    const void *body;
    size_t body_len;
} response;

static void send_response(int fd, const response *r)
{
    char head[512];
    int n = snprintf(head, sizeof head,
                     "HTTP/1.1 %d %s\r\n"
                     "Content-Length: %zu\r\n"
                     "Connection: close\r\n"
                     "%s%s%s"
                     "%s%s%s"
                     "\r\n",
                     r->status, status_text(r->status), r->body_len,
                     r->content_type ? "Content-Type: " : "",
                     r->content_type ? r->content_type : "",
                     r->content_type ? "\r\n" : "",
                     r->allow ? "Allow: " : "", r->allow ? r->allow : "",
                     r->allow ? "\r\n" : "");
    if (n < 0 || (size_t)n >= sizeof head)
        return;

    struct iovec iov[2] = {
        { .iov_base = head, .iov_len = (size_t)n },
        { .iov_base = (void *)r->body, .iov_len = r->body_len },
    };
    write_all(fd, iov, r->body_len ? 2 : 1);
}

static void send_simple(int fd, int status)
{
    send_response(fd, &(response){ .status = status });
}

static void send_text(int fd, int status, const char *text)
{
    send_response(fd, &(response){ .status = status,
                                   .content_type = "text/plain; charset=utf-8",
                                   .body = text,
                                   .body_len = strlen(text) });
}

static void send_not_allowed(int fd, const char *allow)
{
    send_response(fd, &(response){ .status = 405, .allow = allow });
}

/* ------------------------------------------------------------------------ */
/* Request parsing                                                          */

typedef struct {
    char *method;
    char *target;
    bool has_length;
    size_t content_length;
    bool chunked;
    /* Body bytes already received together with the header block. */
    unsigned char *extra;
    size_t extra_len;
} request;

static bool is_tchar(unsigned char c)
{
    return (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') ||
           (c >= '0' && c <= '9') || strchr("!#$%&'*+-.^_`|~", c) != NULL;
}

static void trim_ows(char **s, char **end)
{
    while (*s < *end && (**s == ' ' || **s == '\t'))
        (*s)++;
    while (*end > *s && ((*end)[-1] == ' ' || (*end)[-1] == '\t'))
        (*end)--;
}

/* Parses a non-empty run of decimal digits into *out, rejecting overflow. */
static bool parse_size(const char *s, const char *end, size_t *out)
{
    if (s == end)
        return false;
    size_t v = 0;
    for (; s < end; s++) {
        if (*s < '0' || *s > '9')
            return false;
        unsigned d = (unsigned)(*s - '0');
        if (v > (SIZE_MAX - d) / 10)
            return false;
        v = v * 10 + d;
    }
    *out = v;
    return true;
}

/* Parses the header block in buf[0..len) (terminated by CRLFCRLF, which is
 * not included in len). Modifies buf in place. Returns 0 or an HTTP status. */
static int parse_head(char *buf, size_t len, request *req)
{
    char *end = buf + len;
    char *line_end = memchr(buf, '\r', len);
    if (!line_end)
        line_end = end;

    /* Request line: method SP target SP version */
    char *sp1 = memchr(buf, ' ', (size_t)(line_end - buf));
    if (!sp1 || sp1 == buf)
        return 400;
    char *sp2 = memchr(sp1 + 1, ' ', (size_t)(line_end - sp1 - 1));
    if (!sp2 || sp2 == sp1 + 1)
        return 400;
    for (char *p = buf; p < sp1; p++)
        if (!is_tchar((unsigned char)*p))
            return 400;
    size_t vlen = (size_t)(line_end - sp2 - 1);
    if (vlen != 8 || memcmp(sp2 + 1, "HTTP/1.", 7) != 0)
        return (vlen >= 5 && memcmp(sp2 + 1, "HTTP/", 5) == 0) ? 505 : 400;

    *sp1 = '\0';
    *sp2 = '\0';
    req->method = buf;
    req->target = sp1 + 1;

    /* Header fields */
    char *p = line_end;
    while (p < end) {
        if (end - p < 2 || p[0] != '\r' || p[1] != '\n')
            return 400;
        p += 2;
        char *eol = memchr(p, '\r', (size_t)(end - p));
        if (!eol)
            eol = end;
        char *colon = memchr(p, ':', (size_t)(eol - p));
        if (!colon || colon == p)
            return 400;
        for (char *q = p; q < colon; q++)
            if (!is_tchar((unsigned char)*q))
                return 400;

        size_t nlen = (size_t)(colon - p);
        char *val = colon + 1;
        char *vend = eol;
        trim_ows(&val, &vend);

        if (nlen == 14 && strncasecmp(p, "Content-Length", 14) == 0) {
            size_t cl;
            if (!parse_size(val, vend, &cl))
                return 400;
            if (req->has_length && cl != req->content_length)
                return 400;
            req->has_length = true;
            req->content_length = cl;
        } else if (nlen == 17 && strncasecmp(p, "Transfer-Encoding", 17) == 0) {
            req->chunked = true;
        }
        p = eol;
    }

    if (req->chunked)
        return req->has_length ? 400 : 501;
    return 0;
}

/* ------------------------------------------------------------------------ */
/* Routing                                                                  */

static bool valid_key(const char *k)
{
    size_t n = 0;
    for (; k[n]; n++) {
        unsigned char c = (unsigned char)k[n];
        bool ok = (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') ||
                  (c >= '0' && c <= '9') || c == '_' || c == '-';
        if (!ok || n >= MAX_KEY_LEN)
            return false;
    }
    return n > 0;
}

/* Builds the JSON array of keys. Keys are restricted to [A-Za-z0-9_-], so no
 * escaping is required. */
static char *keys_to_json(const kv_keys *keys, size_t *out_len)
{
    size_t cap = 2;
    for (size_t i = 0; i < keys->count; i++)
        cap += strlen(keys->keys[i]) + 3;
    char *buf = malloc(cap + 1);
    if (!buf)
        return NULL;

    char *p = buf;
    *p++ = '[';
    for (size_t i = 0; i < keys->count; i++) {
        if (i)
            *p++ = ',';
        *p++ = '"';
        size_t n = strlen(keys->keys[i]);
        memcpy(p, keys->keys[i], n);
        p += n;
        *p++ = '"';
    }
    *p++ = ']';
    *p = '\0';
    *out_len = (size_t)(p - buf);
    return buf;
}

static void handle_list(int fd)
{
    kv_keys keys;
    if (kv_list(g_store, &keys) != 0) {
        send_simple(fd, 500);
        return;
    }
    size_t len = 0;
    char *json = keys_to_json(&keys, &len);
    kv_keys_free(&keys);
    if (!json) {
        send_simple(fd, 500);
        return;
    }
    send_response(fd, &(response){ .status = 200,
                                   .content_type = "application/json",
                                   .body = json,
                                   .body_len = len });
    free(json);
}

static void handle_get(int fd, const char *key)
{
    kv_value v;
    if (!kv_get(g_store, key, &v)) {
        send_simple(fd, 404);
        return;
    }
    if (v.len > 0 && !v.data) {
        send_simple(fd, 500);
        return;
    }
    send_response(fd, &(response){ .status = 200,
                                   .content_type = "application/octet-stream",
                                   .body = v.data,
                                   .body_len = v.len });
    kv_value_free(&v);
}

static void handle_put(int fd, const char *key, request *req)
{
    size_t len = req->content_length;
    if (len > MAX_VALUE_BYTES) {
        send_simple(fd, 413);
        return;
    }

    unsigned char *data = NULL;
    if (len > 0) {
        data = malloc(len);
        if (!data) {
            send_simple(fd, 500);
            return;
        }
        size_t have = req->extra_len < len ? req->extra_len : len;
        memcpy(data, req->extra, have);
        if (!read_exact(fd, data + have, len - have)) {
            free(data);
            return; /* client went away or timed out */
        }
    }
    req->extra_len = 0;

    int rc = kv_put(g_store, key, data, len);
    if (rc < 0)
        send_simple(fd, 500);
    else
        send_simple(fd, rc ? 201 : 200);
}

static void route(int fd, request *req)
{
    const char *m = req->method;
    const char *t = req->target;

    if (strcmp(t, "/health") == 0) {
        if (strcmp(m, "GET") == 0)
            send_text(fd, 200, "ok");
        else
            send_not_allowed(fd, "GET");
        return;
    }

    if (strcmp(t, "/kv") == 0) {
        if (strcmp(m, "GET") == 0)
            handle_list(fd);
        else
            send_not_allowed(fd, "GET");
        return;
    }

    if (strncmp(t, "/kv/", 4) == 0) {
        const char *key = t + 4;
        if (!valid_key(key))
            send_simple(fd, 400);
        else if (strcmp(m, "GET") == 0)
            handle_get(fd, key);
        else if (strcmp(m, "PUT") == 0)
            handle_put(fd, key, req);
        else if (strcmp(m, "DELETE") == 0)
            send_simple(fd, kv_delete(g_store, key) ? 204 : 404);
        else
            send_not_allowed(fd, "GET, PUT, DELETE");
        return;
    }

    send_simple(fd, 404);
}

/* ------------------------------------------------------------------------ */
/* Connection handling                                                      */

static void serve_connection(int fd)
{
    char buf[MAX_HEADER_BYTES + 1];
    size_t used = 0;
    char *head_end = NULL;

    while (!head_end) {
        if (used == MAX_HEADER_BYTES) {
            send_simple(fd, 431);
            return;
        }
        ssize_t n = read_some(fd, buf + used, MAX_HEADER_BYTES - used);
        if (n < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) {
            if (used > 0)
                send_simple(fd, 408);
            return;
        }
        if (n <= 0)
            return;
        size_t from = used >= 3 ? used - 3 : 0;
        used += (size_t)n;
        buf[used] = '\0';
        head_end = strstr(buf + from, "\r\n\r\n");
        /* An embedded NUL would hide the terminator from strstr. */
        if (!head_end && memchr(buf + from, '\0', used - from)) {
            send_simple(fd, 400);
            return;
        }
    }

    request req = { 0 };
    int status = parse_head(buf, (size_t)(head_end - buf), &req);
    if (status) {
        send_simple(fd, status);
        return;
    }
    req.extra = (unsigned char *)head_end + 4;
    req.extra_len = used - (size_t)(head_end + 4 - buf);
    route(fd, &req);
}

static void *connection_thread(void *arg)
{
    int fd = (int)(intptr_t)arg;
    serve_connection(fd);
    lingering_close(fd);
    return NULL;
}

static void configure_client(int fd)
{
    struct timeval tv = { .tv_sec = IO_TIMEOUT_SEC };
    int one = 1;
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof tv);
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof tv);
    setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &one, sizeof one);
#ifdef SO_NOSIGPIPE
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof one);
#endif
}

static int listen_on(int port)
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
        .sin_port = htons((uint16_t)port),
        .sin_addr.s_addr = htonl(INADDR_LOOPBACK),
    };
    if (bind(fd, (struct sockaddr *)&addr, sizeof addr) < 0) {
        perror("bind");
        close(fd);
        return -1;
    }
    if (listen(fd, SOMAXCONN) < 0) {
        perror("listen");
        close(fd);
        return -1;
    }
    return fd;
}

static int parse_port(const char *s)
{
    char *end;
    errno = 0;
    long v = strtol(s, &end, 10);
    if (errno || end == s || *end || v < 1 || v > 65535)
        return -1;
    return (int)v;
}

int main(int argc, char **argv)
{
    if (argc != 2) {
        fprintf(stderr, "usage: %s <port>\n", argv[0]);
        return 2;
    }
    int port = parse_port(argv[1]);
    if (port < 0) {
        fprintf(stderr, "invalid port: %s\n", argv[1]);
        return 2;
    }

    signal(SIGPIPE, SIG_IGN);

    g_store = kv_store_new();
    if (!g_store) {
        fprintf(stderr, "out of memory\n");
        return 1;
    }

    int lfd = listen_on(port);
    if (lfd < 0)
        return 1;

    pthread_attr_t attr;
    pthread_attr_init(&attr);
    pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_DETACHED);
    /* Headers live on the stack; leave ample headroom. */
    pthread_attr_setstacksize(&attr, 256 * 1024);

    for (;;) {
        int cfd = accept(lfd, NULL, NULL);
        if (cfd < 0) {
            if (errno == EINTR || errno == ECONNABORTED)
                continue;
            if (errno == EMFILE || errno == ENFILE || errno == ENOBUFS ||
                errno == ENOMEM) {
                usleep(10 * 1000); /* resource pressure: back off briefly */
                continue;
            }
            perror("accept");
            return 1;
        }
        configure_client(cfd);

        pthread_t tid;
        if (pthread_create(&tid, &attr, connection_thread,
                           (void *)(intptr_t)cfd) != 0) {
            send_simple(cfd, 500);
            close(cfd);
        }
    }
}
