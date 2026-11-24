#include "server.h"

#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <poll.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <time.h>
#include <unistd.h>

#include "http.h"
#include "routes.h"

enum {
    MAX_CONNS = 4096,
    MAX_HEAD = 64 * 1024,
    INITIAL_BUF = 8 * 1024,
    IO_TIMEOUT_SEC = 30,   /* overall budget for receiving + sending */
    DRAIN_TIMEOUT_SEC = 2, /* lingering close after the response */
    POLL_TICK_MS = 1000,
};

typedef enum {
    ST_READ_HEAD,
    ST_READ_BODY,
    ST_WRITE,
    ST_DRAIN,
} conn_state;

typedef struct {
    int fd;
    conn_state state;
    time_t deadline;

    char *in;
    size_t in_len, in_cap;
    size_t head_len;
    http_request req;

    char *out;
    size_t out_len, out_off;
    bool continue_pending; /* need to send "100 Continue" before reading */
} conn;

static const char CONTINUE_LINE[] = "HTTP/1.1 100 Continue\r\n\r\n";

static time_t now_sec(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec;
}

static int set_nonblocking(int fd)
{
    int flags = fcntl(fd, F_GETFL);
    if (flags < 0 || fcntl(fd, F_SETFL, flags | O_NONBLOCK) < 0)
        return -1;
    return 0;
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
    if (bind(fd, (struct sockaddr *)&addr, sizeof addr) < 0) {
        perror("bind");
        close(fd);
        return -1;
    }
    if (listen(fd, SOMAXCONN) < 0 || set_nonblocking(fd) < 0) {
        perror("listen");
        close(fd);
        return -1;
    }
    return fd;
}

static void conn_free(conn *c)
{
    close(c->fd);
    free(c->in);
    free(c->out);
    free(c);
}

static conn *conn_new(int fd)
{
    conn *c = calloc(1, sizeof *c);
    if (!c)
        return NULL;
    c->in = malloc(INITIAL_BUF);
    if (!c->in) {
        free(c);
        return NULL;
    }
    c->fd = fd;
    c->in_cap = INITIAL_BUF;
    c->state = ST_READ_HEAD;
    c->deadline = now_sec() + IO_TIMEOUT_SEC;
    return c;
}

/* Installs a response and switches the connection to writing. */
static void conn_respond(conn *c, char *resp, size_t len)
{
    free(c->out);
    c->out = resp;
    c->out_len = len;
    c->out_off = 0;
    c->continue_pending = false;
    c->state = ST_WRITE;
}

/* Returns false if even an error response cannot be produced. */
static bool conn_fail(conn *c, int status)
{
    char *resp;
    size_t len;
    if (route_error(status, &resp, &len) != 0)
        return false;
    conn_respond(c, resp, len);
    return true;
}

static bool reserve(conn *c, size_t need)
{
    if (need <= c->in_cap)
        return true;
    size_t cap = c->in_cap;
    while (cap < need)
        cap *= 2;
    /* The parsed request points into c->in; carry its slices across the move. */
    bool parsed = c->head_len != 0;
    size_t method_off = parsed ? (size_t)(c->req.method.ptr - c->in) : 0;
    size_t target_off = parsed ? (size_t)(c->req.target.ptr - c->in) : 0;
    char *p = realloc(c->in, cap);
    if (!p)
        return false;
    c->in = p;
    if (parsed) {
        c->req.method.ptr = p + method_off;
        c->req.target.ptr = p + target_off;
    }
    c->in_cap = cap;
    return true;
}

static bool dispatch(conn *c, kv_store *store)
{
    char *resp;
    size_t len;
    if (route_request(store, &c->req, c->in + c->head_len, &resp, &len) != 0)
        return false;
    conn_respond(c, resp, len);
    return true;
}

/* Advances the parser after new input. Returns false to drop the connection. */
static bool process_input(conn *c, kv_store *store)
{
    if (c->state == ST_READ_HEAD) {
        c->head_len = http_head_length(c->in, c->in_len);
        if (c->head_len == 0) {
            if (c->in_len >= MAX_HEAD)
                return conn_fail(c, 431);
            return true;
        }
        int rc = http_parse_head(c->in, c->head_len, &c->req);
        if (rc)
            return conn_fail(c, rc);
        if (c->req.content_length > KV_MAX_VALUE_LEN)
            return conn_fail(c, 413);
        if (!reserve(c, c->head_len + c->req.content_length))
            return conn_fail(c, 500);
        c->state = ST_READ_BODY;
        if (c->req.expect_continue && c->in_len < c->head_len + c->req.content_length)
            c->continue_pending = true;
    }
    if (c->state == ST_READ_BODY &&
        c->in_len >= c->head_len + c->req.content_length)
        return dispatch(c, store);
    return true;
}

/* Returns false when the connection should be closed. */
static bool on_readable(conn *c, kv_store *store)
{
    for (;;) {
        if (c->state == ST_DRAIN) {
            char scratch[16 * 1024];
            ssize_t n = recv(c->fd, scratch, sizeof scratch, 0);
            if (n > 0)
                continue;
            if (n < 0 && (errno == EAGAIN || errno == EWOULDBLOCK))
                return true;
            if (n < 0 && errno == EINTR)
                continue;
            return false; /* EOF or error: peer is done */
        }
        if (c->state != ST_READ_HEAD && c->state != ST_READ_BODY)
            return true;

        if (c->in_len == c->in_cap) {
            /* Only the head phase can fill the buffer; the body was reserved. */
            if (c->state != ST_READ_HEAD || !reserve(c, c->in_cap * 2))
                return conn_fail(c, 500);
        }
        size_t room = c->in_cap - c->in_len;
        if (c->state == ST_READ_HEAD && c->in_len + room > MAX_HEAD)
            room = c->in_len < MAX_HEAD ? MAX_HEAD - c->in_len : 0;
        if (c->state == ST_READ_BODY) {
            size_t want = c->head_len + c->req.content_length;
            room = want > c->in_len ? want - c->in_len : 0;
        }
        if (room == 0)
            return process_input(c, store);

        ssize_t n = recv(c->fd, c->in + c->in_len, room, 0);
        if (n > 0) {
            c->in_len += (size_t)n;
            if (!process_input(c, store))
                return false;
            continue;
        }
        if (n == 0)
            return false; /* client went away before finishing its request */
        if (errno == EAGAIN || errno == EWOULDBLOCK)
            return true;
        if (errno == EINTR)
            continue;
        return false;
    }
}

static bool on_writable(conn *c)
{
    if (c->continue_pending) {
        /* Best effort: the interim line is tiny and fits in the send buffer. */
        ssize_t n = send(c->fd, CONTINUE_LINE, sizeof CONTINUE_LINE - 1, 0);
        if (n < 0 && errno != EAGAIN && errno != EWOULDBLOCK && errno != EINTR)
            return false;
        if (n >= 0)
            c->continue_pending = false;
        return true;
    }
    while (c->state == ST_WRITE && c->out_off < c->out_len) {
        ssize_t n = send(c->fd, c->out + c->out_off, c->out_len - c->out_off, 0);
        if (n > 0) {
            c->out_off += (size_t)n;
            continue;
        }
        if (n < 0 && errno == EINTR)
            continue;
        if (n < 0 && (errno == EAGAIN || errno == EWOULDBLOCK))
            return true;
        return false;
    }
    if (c->state == ST_WRITE) {
        /* Response fully sent: half-close and drain so that unread request
         * bytes do not trigger a RST that could discard the response. */
        free(c->out);
        c->out = NULL;
        free(c->in);
        c->in = NULL;
        c->in_len = c->in_cap = 0;
        shutdown(c->fd, SHUT_WR);
        c->state = ST_DRAIN;
        c->deadline = now_sec() + DRAIN_TIMEOUT_SEC;
    }
    return true;
}

static short wanted_events(const conn *c)
{
    switch (c->state) {
    case ST_READ_HEAD:
    case ST_READ_BODY:
        return c->continue_pending ? (POLLIN | POLLOUT) : POLLIN;
    case ST_WRITE:
        return POLLOUT;
    case ST_DRAIN:
        return POLLIN;
    }
    return 0;
}

static void accept_all(int lfd, conn **conns, size_t *nconns)
{
    while (*nconns < MAX_CONNS) {
        int fd = accept(lfd, NULL, NULL);
        if (fd < 0) {
            if (errno == EINTR || errno == ECONNABORTED)
                continue;
            if (errno != EAGAIN && errno != EWOULDBLOCK)
                perror("accept");
            return;
        }
        int one = 1;
        setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &one, sizeof one);
#ifdef SO_NOSIGPIPE
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof one);
#endif
        conn *c = set_nonblocking(fd) == 0 ? conn_new(fd) : NULL;
        if (!c) {
            close(fd);
            continue;
        }
        conns[(*nconns)++] = c;
    }
}

int server_run(uint16_t port, kv_store *store)
{
    int lfd = listen_on(port);
    if (lfd < 0)
        return 1;

    conn **conns = calloc(MAX_CONNS, sizeof *conns);
    struct pollfd *pfds = calloc(MAX_CONNS + 1, sizeof *pfds);
    if (!conns || !pfds) {
        fprintf(stderr, "out of memory\n");
        return 1;
    }
    size_t nconns = 0;

    for (;;) {
        pfds[0] = (struct pollfd){.fd = lfd, .events = nconns < MAX_CONNS ? POLLIN : 0};
        for (size_t i = 0; i < nconns; i++)
            pfds[i + 1] = (struct pollfd){.fd = conns[i]->fd, .events = wanted_events(conns[i])};

        int ready = poll(pfds, (nfds_t)nconns + 1, POLL_TICK_MS);
        if (ready < 0) {
            if (errno == EINTR)
                continue;
            perror("poll");
            return 1;
        }

        time_t now = now_sec();
        size_t polled = nconns;
        size_t kept = 0;
        for (size_t i = 0; i < polled; i++) {
            conn *c = conns[i];
            short re = pfds[i + 1].revents;
            bool alive = true;

            if (re & (POLLIN | POLLHUP | POLLERR))
                alive = on_readable(c, store);
            if (alive && (re & (POLLOUT | POLLERR)))
                alive = on_writable(c);
            /* A freshly produced response is usually writable right away. */
            if (alive && c->state == ST_WRITE && !(re & POLLOUT))
                alive = on_writable(c);
            if (alive && now >= c->deadline)
                alive = false;

            if (alive)
                conns[kept++] = c;
            else
                conn_free(c);
        }
        nconns = kept;

        if (pfds[0].revents & POLLIN)
            accept_all(lfd, conns, &nconns);
    }
}
