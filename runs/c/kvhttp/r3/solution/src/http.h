/* Minimal HTTP/1.1 request-head parsing and response formatting. */
#ifndef KVHTTP_HTTP_H
#define KVHTTP_HTTP_H

#include <stdbool.h>
#include <stddef.h>

typedef struct {
    const char *ptr;
    size_t len;
} http_slice;

typedef struct {
    http_slice method;
    http_slice target;
    size_t content_length;
    bool expect_continue;
} http_request;

/* Returns the length of the request head (through the blank line) if buf
 * contains a complete head, otherwise 0. */
size_t http_head_length(const char *buf, size_t len);

/* Parses a complete request head of length head_len. Returns 0 on success or
 * an HTTP status code (400, 501, 505) describing why the request is invalid.
 * Slices in *req point into buf. */
int http_parse_head(const char *buf, size_t head_len, http_request *req);

bool http_slice_eq(http_slice s, const char *lit);

const char *http_reason(int status);

/* Builds a complete response (head + body) in a freshly malloc'd buffer.
 * content_type may be NULL. Returns NULL on allocation failure. */
char *http_build_response(int status, const char *content_type,
                          const void *body, size_t body_len, size_t *out_len);

#endif
