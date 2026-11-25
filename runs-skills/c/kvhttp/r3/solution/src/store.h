#ifndef KVHTTP_STORE_H
#define KVHTTP_STORE_H

#include <stdbool.h>
#include <stddef.h>

/* Thread-safe in-memory key/value store. Keys are NUL-free byte strings,
 * values are arbitrary byte sequences. */
typedef struct kv_store kv_store;

kv_store *kv_store_new(void);
void kv_store_free(kv_store *s);

/* Takes ownership of `value` (malloc'd, `len` bytes; may be NULL if len == 0).
 * On success sets *created to true if the key did not exist before.
 * Returns 0 or ENOMEM (in which case ownership of `value` stays with the caller). */
int kv_store_put(kv_store *s, const char *key, size_t key_len,
                 void *value, size_t len, bool *created);

/* Copies the value into a fresh malloc'd buffer returned in *out / *out_len.
 * Returns 0, ENOENT if absent, or ENOMEM. */
int kv_store_get(kv_store *s, const char *key, size_t key_len,
                 void **out, size_t *out_len);

/* Returns 0 if deleted, ENOENT if absent. */
int kv_store_delete(kv_store *s, const char *key, size_t key_len);

/* Builds a JSON array of all keys sorted ascending (bytewise) into a fresh
 * malloc'd buffer. Keys must not need JSON escaping.
 * Returns 0 or ENOMEM. */
int kv_store_keys_json(kv_store *s, char **out, size_t *out_len);

#endif
