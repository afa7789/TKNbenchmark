#define _DARWIN_C_SOURCE
#define _POSIX_C_SOURCE 200809L

#include <arpa/inet.h>
#include <errno.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <pthread.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <unistd.h>

#include "http.h"
#include "kvstore.h"

enum { KEY_MAX_LEN = 64, IO_TIMEOUT_SEC = 15 };

static kv_store *g_store;

static bool valid_key(const char *k, size_t len)
{
    if (len == 0 || len > KEY_MAX_LEN)
        return false;
    for (size_t i = 0; i < len; i++) {
        unsigned char c = (unsigned char)k[i];
        bool ok = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
                  (c >= '0' && c <= '9') || c == '_' || c == '-';
        if (!ok)
            return false;
    }
    return true;
}

static int send_status(int fd, int status)
{
    return http_send_response(fd, status, NULL, NULL, 0);
}

static int send_405(int fd, const char *allow)
{
    char hdr[64];
    snprintf(hdr, sizeof hdr, "Allow: %s\r\n", allow);
    return http_send_response(fd, 405, hdr, NULL, 0);
}

static void handle_list(int fd)
{
    kv_key *keys = NULL;
    size_t n = 0;
    if (kv_keys(g_store, &keys, &n) != 0) {
        send_status(fd, 500);
        return;
    }

    /* Keys are restricted to [A-Za-z0-9_-], so no JSON escaping is needed. */
    size_t cap = 2;
    for (size_t i = 0; i < n; i++)
        cap += keys[i].len + 3; /* quotes + comma */
    char *json = malloc(cap);
    if (!json) {
        kv_keys_free(keys, n);
        send_status(fd, 500);
        return;
    }
    size_t len = 0;
    json[len++] = '[';
    for (size_t i = 0; i < n; i++) {
        if (i > 0)
            json[len++] = ',';
        json[len++] = '"';
        memcpy(json + len, keys[i].data, keys[i].len);
        len += keys[i].len;
        json[len++] = '"';
    }
    json[len++] = ']';
    kv_keys_free(keys, n);

    http_send_response(fd, 200, "Content-Type: application/json\r\n", json, len);
    free(json);
}

static void handle_key(int fd, http_request *req, const char *key, size_t klen)
{
    const char *m = req->method;

    if (strcmp(m, "GET") == 0) {
        uint8_t *val = NULL;
        size_t vlen = 0;
        int rc = kv_get(g_store, key, klen, &val, &vlen);
        if (rc == ENOENT) {
            send_status(fd, 404);
        } else if (rc != 0) {
            send_status(fd, 500);
        } else {
            http_send_response(fd, 200, "Content-Type: application/octet-stream\r\n", val, vlen);
            free(val);
        }
    } else if (strcmp(m, "PUT") == 0) {
        if (req->body_too_large) {
            send_status(fd, 413);
            return;
        }
        uint8_t *val = req->body ? req->body : malloc(1);
        if (!val) {
            send_status(fd, 500);
            return;
        }
        bool created = false;
        if (kv_put(g_store, key, klen, val, req->body_len, &created) != 0) {
            if (val != req->body)
                free(val);
            send_status(fd, 500);
            return;
        }
        req->body = NULL; /* ownership moved into the store */
        send_status(fd, created ? 201 : 200);
    } else if (strcmp(m, "DELETE") == 0) {
        send_status(fd, kv_delete(g_store, key, klen) ? 204 : 404);
    } else {
        send_405(fd, "GET, PUT, DELETE");
    }
}

static void route(int fd, http_request *req)
{
    static const char kv_prefix[] = "/kv/";
    const size_t kv_prefix_len = sizeof kv_prefix - 1;
    const char *path = req->path;
    bool is_get = strcmp(req->method, "GET") == 0;

    if (strcmp(path, "/health") == 0) {
        if (is_get)
            http_send_response(fd, 200, "Content-Type: text/plain\r\n", "ok", 2);
        else
            send_405(fd, "GET");
    } else if (strcmp(path, "/kv") == 0) {
        if (is_get)
            handle_list(fd);
        else
            send_405(fd, "GET");
    } else if (strncmp(path, kv_prefix, kv_prefix_len) == 0) {
        const char *key = path + kv_prefix_len;
        size_t klen = req->path_len - kv_prefix_len;
        if (!valid_key(key, klen))
            send_status(fd, 400);
        else
            handle_key(fd, req, key, klen);
    } else {
        send_status(fd, 404);
    }
}

static void *connection_main(void *arg)
{
    int fd = (int)(intptr_t)arg;

    http_request req;
    int status = http_read_request(fd, &req);
    if (status == 0)
        route(fd, &req);
    else if (status > 0)
        send_status(fd, status);
    http_request_free(&req);

    http_close_gracefully(fd);
    return NULL;
}

static void configure_client(int fd)
{
    struct timeval tv = {.tv_sec = IO_TIMEOUT_SEC};
    int one = 1;
    (void)setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof tv);
    (void)setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof tv);
    (void)setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &one, sizeof one);
#ifdef SO_NOSIGPIPE
    (void)setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof one);
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
    (void)setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof one);

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

    g_store = kv_create();
    if (!g_store) {
        fprintf(stderr, "out of memory\n");
        return EXIT_FAILURE;
    }

    int lfd = listen_on(port);
    if (lfd < 0)
        return EXIT_FAILURE;

    pthread_attr_t attr;
    pthread_attr_init(&attr);
    pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_DETACHED);

    for (;;) {
        int cfd = accept(lfd, NULL, NULL);
        if (cfd < 0) {
            if (errno == EINTR || errno == ECONNABORTED)
                continue;
            if (errno == EMFILE || errno == ENFILE || errno == ENOBUFS || errno == ENOMEM) {
                usleep(10000); /* resource pressure: back off and retry */
                continue;
            }
            perror("accept");
            break;
        }
        configure_client(cfd);

        pthread_t tid;
        int rc = pthread_create(&tid, &attr, connection_main, (void *)(intptr_t)cfd);
        if (rc != 0) {
            send_status(cfd, 500);
            close(cfd);
        }
    }

    pthread_attr_destroy(&attr);
    close(lfd);
    kv_destroy(g_store);
    return EXIT_FAILURE;
}
