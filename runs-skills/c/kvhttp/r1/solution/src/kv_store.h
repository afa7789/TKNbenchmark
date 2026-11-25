#ifndef KVHTTP_KV_STORE_H
#define KVHTTP_KV_STORE_H

#include <stdbool.h>
#include <stddef.h>

#define KV_KEY_MAX 64

/* Immutable, reference-counted value buffer. Readers hold a reference while
 * sending, so the store lock is never held across network I/O. */
typedef struct kv_value kv_value;

kv_value *kv_value_new(const void *data, size_t len);
void kv_value_retain(kv_value *v);
void kv_value_release(kv_value *v);
const unsigned char *kv_value_data(const kv_value *v);
size_t kv_value_len(const kv_value *v);

typedef struct kv_store kv_store;

kv_store *kv_store_new(void);
void kv_store_free(kv_store *s);

/* Returns true if key is a valid key: [A-Za-z0-9_-]{1,KV_KEY_MAX}. */
bool kv_key_valid(const char *key, size_t len);

/* Stores v under key (taking over the caller's reference). *created is set to
 * true if the key was new. Returns 0 or ENOMEM (caller keeps v on failure). */
int kv_store_put(kv_store *s, const char *key, size_t klen, kv_value *v, bool *created);

/* Returns a new reference to the value, or NULL if absent. */
kv_value *kv_store_get(kv_store *s, const char *key, size_t klen);

/* Returns true if the key existed and was removed. */
bool kv_store_delete(kv_store *s, const char *key, size_t klen);

/* Snapshot of all keys, sorted ascending (bytewise). On success *out is a
 * malloc'd array of *count malloc'd NUL-terminated strings; free with
 * kv_keys_free. Returns 0 or ENOMEM. */
int kv_store_keys(kv_store *s, char ***out, size_t *count);
void kv_keys_free(char **keys, size_t count);

#endif
