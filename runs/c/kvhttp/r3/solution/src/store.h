/* In-memory key-value store: a separately chained hash table. */
#ifndef KVHTTP_STORE_H
#define KVHTTP_STORE_H

#include <stdbool.h>
#include <stddef.h>

typedef struct kv_store kv_store;

kv_store *kv_create(void);
void kv_destroy(kv_store *s);

/* Stores a copy of val under key. Sets *created to true if the key was new.
 * Returns 0 on success, -1 on allocation failure (store left unchanged). */
int kv_put(kv_store *s, const char *key, size_t klen,
           const void *val, size_t vlen, bool *created);

/* Looks up key. On hit returns true and points *val and *vlen at the stored
 * bytes; the pointer is valid until the next mutation of the store. */
bool kv_get(const kv_store *s, const char *key, size_t klen,
            const void **val, size_t *vlen);

/* Removes key. Returns true if it was present. */
bool kv_delete(kv_store *s, const char *key, size_t klen);

size_t kv_count(const kv_store *s);

/* Fills out[0..kv_count) with NUL-terminated key pointers, unordered.
 * The pointers are valid until the next mutation of the store. */
void kv_keys(const kv_store *s, const char **out);

#endif
