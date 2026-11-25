#ifndef KVHTTP_KVSTORE_H
#define KVHTTP_KVSTORE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

/* Thread-safe in-memory key/value store. Keys are arbitrary byte strings of
 * known length (validation is the caller's job); values are opaque bytes. */
typedef struct kv_store kv_store;

/* A key returned by kv_keys(); NUL-terminated for convenience. */
typedef struct {
    size_t len;
    char *data;
} kv_key;

kv_store *kv_create(void);
void kv_destroy(kv_store *s);

/* Store `val` under `key`, taking ownership of `val` (allocated with malloc)
 * on success. *created reports whether the key was new.
 * Returns 0 or ENOMEM (in which case the caller still owns `val`). */
int kv_put(kv_store *s, const char *key, size_t klen, uint8_t *val, size_t vlen,
           bool *created);

/* Copy the value for `key` into a fresh malloc'd buffer.
 * Returns 0, ENOENT, or ENOMEM. */
int kv_get(kv_store *s, const char *key, size_t klen, uint8_t **out, size_t *outlen);

/* Returns true if the key existed and was removed. */
bool kv_delete(kv_store *s, const char *key, size_t klen);

/* Snapshot all keys, sorted ascending by byte value. Free with kv_keys_free().
 * Returns 0 or ENOMEM. */
int kv_keys(kv_store *s, kv_key **out, size_t *count);
void kv_keys_free(kv_key *keys, size_t count);

#endif /* KVHTTP_KVSTORE_H */
