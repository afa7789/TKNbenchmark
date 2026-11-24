#include "routes.h"

#include <stdbool.h>
#include <stdlib.h>
#include <string.h>

static int respond(int status, const char *type, const void *body, size_t len,
                   char **out, size_t *out_len)
{
    *out = http_build_response(status, type, body, len, out_len);
    return *out ? 0 : -1;
}

int route_error(int status, char **out, size_t *out_len)
{
    return respond(status, NULL, NULL, 0, out, out_len);
}

static bool valid_key(http_slice k)
{
    if (k.len < 1 || k.len > KV_MAX_KEY_LEN)
        return false;
    for (size_t i = 0; i < k.len; i++) {
        char c = k.ptr[i];
        bool ok = (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') ||
                  (c >= '0' && c <= '9') || c == '_' || c == '-';
        if (!ok)
            return false;
    }
    return true;
}

static int cmp_keys(const void *a, const void *b)
{
    return strcmp(*(const char *const *)a, *(const char *const *)b);
}

/* Keys are restricted to [A-Za-z0-9_-], so no JSON escaping is required. */
static int list_keys(const kv_store *store, char **out, size_t *out_len)
{
    size_t n = kv_count(store);
    const char **keys = malloc((n ? n : 1) * sizeof *keys);
    if (!keys)
        return route_error(500, out, out_len);
    kv_keys(store, keys);
    qsort(keys, n, sizeof *keys, cmp_keys);

    size_t cap = 2;
    for (size_t i = 0; i < n; i++)
        cap += strlen(keys[i]) + 3; /* quotes and comma */
    char *json = malloc(cap);
    if (!json) {
        free(keys);
        return route_error(500, out, out_len);
    }

    size_t len = 0;
    json[len++] = '[';
    for (size_t i = 0; i < n; i++) {
        if (i)
            json[len++] = ',';
        json[len++] = '"';
        size_t kl = strlen(keys[i]);
        memcpy(json + len, keys[i], kl);
        len += kl;
        json[len++] = '"';
    }
    json[len++] = ']';
    free(keys);

    int rc = respond(200, "application/json", json, len, out, out_len);
    free(json);
    return rc;
}

static int handle_key(kv_store *store, const http_request *req, http_slice key,
                      const char *body, char **out, size_t *out_len)
{
    if (http_slice_eq(req->method, "GET")) {
        const void *val;
        size_t vlen;
        if (!kv_get(store, key.ptr, key.len, &val, &vlen))
            return route_error(404, out, out_len);
        return respond(200, "application/octet-stream", val, vlen, out, out_len);
    }
    if (http_slice_eq(req->method, "PUT")) {
        bool created;
        if (kv_put(store, key.ptr, key.len, body, req->content_length, &created) != 0)
            return route_error(500, out, out_len);
        return route_error(created ? 201 : 200, out, out_len);
    }
    if (http_slice_eq(req->method, "DELETE"))
        return route_error(kv_delete(store, key.ptr, key.len) ? 204 : 404,
                           out, out_len);
    return route_error(405, out, out_len);
}

int route_request(kv_store *store, const http_request *req,
                  const char *body, char **out, size_t *out_len)
{
    http_slice path = req->target;
    static const char kv_prefix[] = "/kv/";
    const size_t kv_prefix_len = sizeof kv_prefix - 1;

    if (http_slice_eq(path, "/health")) {
        if (!http_slice_eq(req->method, "GET"))
            return route_error(405, out, out_len);
        return respond(200, "text/plain", "ok", 2, out, out_len);
    }
    if (http_slice_eq(path, "/kv")) {
        if (!http_slice_eq(req->method, "GET"))
            return route_error(405, out, out_len);
        return list_keys(store, out, out_len);
    }
    if (path.len >= kv_prefix_len && memcmp(path.ptr, kv_prefix, kv_prefix_len) == 0) {
        http_slice key = {path.ptr + kv_prefix_len, path.len - kv_prefix_len};
        if (!valid_key(key))
            return route_error(400, out, out_len);
        return handle_key(store, req, key, body, out, out_len);
    }
    return route_error(404, out, out_len);
}
