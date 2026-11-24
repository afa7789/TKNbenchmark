#ifndef KV_STORE_H
#define KV_STORE_H

#include <stdbool.h>
#include <stddef.h>

/* Thread-safe in-memory key-value store. Keys are NUL-terminated strings,
 * values are arbitrary byte sequences. */
typedef struct kv_store kv_store;

/* A copied-out value; release with kv_value_free(). */
typedef struct {
    unsigned char *data;
    size_t len;
} kv_value;

/* A sorted snapshot of all keys; release with kv_keys_free(). */
typedef struct {
    char **keys;
    size_t count;
} kv_keys;

kv_store *kv_store_new(void);
void kv_store_free(kv_store *s);

/* Takes ownership of `data` (must be malloc'd, or NULL when len == 0).
 * Returns 1 if the key was created, 0 if replaced, -1 on allocation failure
 * (in which case `data` is freed). */
int kv_put(kv_store *s, const char *key, unsigned char *data, size_t len);

/* Returns true and fills *out when present; false when absent.
 * On allocation failure returns true with out->data == NULL and len > 0. */
bool kv_get(kv_store *s, const char *key, kv_value *out);

bool kv_delete(kv_store *s, const char *key);

/* Returns 0 on success, -1 on allocation failure. */
int kv_list(kv_store *s, kv_keys *out);

void kv_value_free(kv_value *v);
void kv_keys_free(kv_keys *k);

#endif
