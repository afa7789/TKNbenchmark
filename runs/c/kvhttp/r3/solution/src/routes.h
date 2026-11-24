/* Maps parsed HTTP requests onto key-value store operations. */
#ifndef KVHTTP_ROUTES_H
#define KVHTTP_ROUTES_H

#include <stddef.h>

#include "http.h"
#include "store.h"

enum { KV_MAX_KEY_LEN = 64, KV_MAX_VALUE_LEN = 1024 * 1024 };

/* Handles one request and returns a malloc'd serialized response in *out.
 * Returns 0 on success, -1 if no response could be allocated. */
int route_request(kv_store *store, const http_request *req,
                  const char *body, char **out, size_t *out_len);

/* Serializes a bodyless error response for the given status. */
int route_error(int status, char **out, size_t *out_len);

#endif
