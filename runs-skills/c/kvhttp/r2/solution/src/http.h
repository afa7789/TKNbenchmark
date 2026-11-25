#ifndef KVHTTP_HTTP_H
#define KVHTTP_HTTP_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

/* Minimal HTTP/1.1 request reading and response writing for one request per
 * connection (the server always answers with Connection: close). */

enum {
    HTTP_MAX_HEADER = 16 * 1024,
    HTTP_MAX_BODY = 1024 * 1024,
};

typedef struct {
    const char *method; /* NUL-terminated, points into the header buffer */
    const char *path;   /* NUL-terminated, points into the header buffer */
    size_t path_len;
    uint8_t *body;      /* malloc'd, NULL when there is no body */
    size_t body_len;
    size_t content_length;
    bool body_too_large; /* Content-Length exceeded HTTP_MAX_BODY; body not read */
    char *header_buf_;   /* owned storage for method/path */
} http_request;

/* Result of http_read_request(): 0 on success, otherwise the HTTP status the
 * server should answer with (400, 431, 501, ...), or -1 when the connection
 * failed and no response can be sent. */
int http_read_request(int fd, http_request *req);
void http_request_free(http_request *req);

/* Send a full response. `extra_headers` (may be NULL) is a block of
 * "Name: value\r\n" lines. Returns 0 or -1 on I/O error. */
int http_send_response(int fd, int status, const char *extra_headers,
                       const void *body, size_t body_len);

/* Half-close and discard any unread input so the peer reliably receives the
 * response instead of a connection reset, then close the socket. */
void http_close_gracefully(int fd);

#endif /* KVHTTP_HTTP_H */
