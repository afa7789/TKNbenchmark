/* Minimal HTTP/1.1 request parsing and response writing over a socket. */
#ifndef KVHTTP_HTTP_H
#define KVHTTP_HTTP_H

#include <stddef.h>

#define HTTP_HEAD_MAX (16 * 1024)

typedef struct {
    /* Request line pieces point into `head` and are NUL-terminated. */
    char *method;
    char *target;
    unsigned char *body; /* malloc'd, NULL when the request has no body */
    size_t body_len;
    char head[HTTP_HEAD_MAX + 1];
} http_request;

/* Reads one request from `fd`, accepting bodies up to `max_body` bytes.
 * Returns 0 on success; a 4xx/5xx status code when the request is
 * malformed and should be answered with that status; or -1 when the peer
 * went away or timed out and no response should be attempted.
 * On every return, http_request_cleanup must be called. */
int http_read_request(int fd, http_request *req, size_t max_body);
void http_request_cleanup(http_request *req);

/* Writes a complete response with Content-Length and Connection: close.
 * `content_type` may be NULL. Returns 0 on success, -1 on I/O error. */
int http_send(int fd, int status, const char *content_type, const void *body, size_t len);

#endif
