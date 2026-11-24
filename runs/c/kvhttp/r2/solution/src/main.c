/* kvhttp: an HTTP/1.1 in-memory key-value server.
 * Usage: ./app <port>  (listens on 127.0.0.1) */
#include "http.h"
#include "store.h"

#include <arpa/inet.h>
#include <errno.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <pthread.h>
#include <signal.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <unistd.h>

#define MAX_VALUE (1024 * 1024)
#define IO_TIMEOUT_SEC 30
#define LINGER_TIMEOUT_MS 500
#define THREAD_STACK (256 * 1024)

static store *g_store;

/* ---------- routing ---------- */

static bool valid_key(const char *k)
{
    size_t n = 0;
    for (; k[n]; n++) {
        unsigned char c = (unsigned char)k[n];
        bool ok = (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') ||
                  c == '_' || c == '-';
        if (!ok || n >= STORE_KEY_MAX)
            return false;
    }
    return n > 0;
}

static int send_empty(int fd, int status) { return http_send(fd, status, NULL, NULL, 0); }

static void handle_list(int fd)
{
    size_t count = 0;
    char **keys = store_keys(g_store, &count);
    if (!keys) {
        send_empty(fd, 500);
        return;
    }
    /* Keys are restricted to [A-Za-z0-9_-], so no JSON escaping is needed. */
    size_t len = 2;
    for (size_t i = 0; i < count; i++)
        len += strlen(keys[i]) + 3;
    char *json = malloc(len + 1);
    if (!json) {
        store_keys_free(keys, count);
        send_empty(fd, 500);
        return;
    }
    char *p = json;
    *p++ = '[';
    for (size_t i = 0; i < count; i++) {
        if (i)
            *p++ = ',';
        *p++ = '"';
        size_t kl = strlen(keys[i]);
        memcpy(p, keys[i], kl);
        p += kl;
        *p++ = '"';
    }
    *p++ = ']';
    store_keys_free(keys, count);
    http_send(fd, 200, "application/json", json, (size_t)(p - json));
    free(json);
}

static void handle_key(int fd, const http_request *req, const char *key)
{
    const char *m = req->method;
    if (strcmp(m, "GET") == 0) {
        blob *b = store_get(g_store, key);
        if (!b) {
            send_empty(fd, 404);
            return;
        }
        http_send(fd, 200, "application/octet-stream", blob_data(b), blob_len(b));
        blob_release(b);
    } else if (strcmp(m, "PUT") == 0) {
        switch (store_put(g_store, key, req->body, req->body_len)) {
        case STORE_CREATED: send_empty(fd, 201); break;
        case STORE_OK: send_empty(fd, 200); break;
        case STORE_NOMEM: send_empty(fd, 500); break;
        }
    } else if (strcmp(m, "DELETE") == 0) {
        send_empty(fd, store_delete(g_store, key) ? 204 : 404);
    } else {
        send_empty(fd, 405);
    }
}

static void route(int fd, const http_request *req)
{
    const char *path = req->target;
    const char *m = req->method;

    if (strcmp(path, "/health") == 0) {
        if (strcmp(m, "GET") == 0)
            http_send(fd, 200, "text/plain", "ok", 2);
        else
            send_empty(fd, 405);
    } else if (strcmp(path, "/kv") == 0) {
        if (strcmp(m, "GET") == 0)
            handle_list(fd);
        else
            send_empty(fd, 405);
    } else if (strncmp(path, "/kv/", 4) == 0) {
        const char *key = path + 4;
        if (!valid_key(key))
            send_empty(fd, 400);
        else
            handle_key(fd, req, key);
    } else {
        send_empty(fd, 404);
    }
}

/* ---------- connection handling ---------- */

/* Half-close and drain so any unread request bytes do not turn our close
 * into a RST that could destroy the response before the client reads it. */
static void lingering_close(int fd)
{
    shutdown(fd, SHUT_WR);
    struct timeval tv = {.tv_sec = 0, .tv_usec = LINGER_TIMEOUT_MS * 1000};
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof tv);
    char sink[4096];
    size_t total = 0;
    while (total < 4 * MAX_VALUE) {
        ssize_t n = recv(fd, sink, sizeof sink, 0);
        if (n < 0 && errno == EINTR)
            continue;
        if (n <= 0)
            break;
        total += (size_t)n;
    }
    close(fd);
}

static void *connection_main(void *arg)
{
    int fd = (int)(intptr_t)arg;

    http_request *req = malloc(sizeof *req);
    if (!req) {
        send_empty(fd, 500);
        lingering_close(fd);
        return NULL;
    }
    int rc = http_read_request(fd, req, MAX_VALUE);
    if (rc == 0)
        route(fd, req);
    else if (rc > 0)
        send_empty(fd, rc);
    http_request_cleanup(req);
    free(req);

    if (rc < 0)
        close(fd);
    else
        lingering_close(fd);
    return NULL;
}

static void configure_client(int fd)
{
    struct timeval tv = {.tv_sec = IO_TIMEOUT_SEC, .tv_usec = 0};
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof tv);
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof tv);
    int one = 1;
    setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &one, sizeof one);
#ifdef SO_NOSIGPIPE
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof one);
#endif
}

static int listen_on(unsigned short port)
{
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) {
        perror("socket");
        return -1;
    }
    int one = 1;
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof one);

    struct sockaddr_in addr = {0};
    addr.sin_family = AF_INET;
    addr.sin_port = htons(port);
    addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
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

static bool parse_port(const char *s, unsigned short *out)
{
    char *end;
    errno = 0;
    long v = strtol(s, &end, 10);
    if (errno || end == s || *end || v < 1 || v > 65535)
        return false;
    *out = (unsigned short)v;
    return true;
}

int main(int argc, char **argv)
{
    unsigned short port;
    if (argc != 2 || !parse_port(argv[1], &port)) {
        fprintf(stderr, "usage: %s <port>\n", argv[0]);
        return 2;
    }
    signal(SIGPIPE, SIG_IGN);

    g_store = store_new();
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
    pthread_attr_setstacksize(&attr, THREAD_STACK);

    for (;;) {
        int cfd = accept(lfd, NULL, NULL);
        if (cfd < 0) {
            if (errno == EINTR || errno == ECONNABORTED)
                continue;
            if (errno == EMFILE || errno == ENFILE || errno == ENOBUFS || errno == ENOMEM) {
                /* Resource exhaustion: back off briefly instead of spinning. */
                usleep(10 * 1000);
                continue;
            }
            perror("accept");
            break;
        }
        configure_client(cfd);
        pthread_t tid;
        if (pthread_create(&tid, &attr, connection_main, (void *)(intptr_t)cfd) != 0) {
            send_empty(cfd, 500);
            close(cfd);
        }
    }

    pthread_attr_destroy(&attr);
    close(lfd);
    store_free(g_store);
    return 1;
}
