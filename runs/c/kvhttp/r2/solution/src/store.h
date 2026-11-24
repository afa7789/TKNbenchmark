/* Thread-safe in-memory key-value store. */
#ifndef KVHTTP_STORE_H
#define KVHTTP_STORE_H

#include <stdbool.h>
#include <stddef.h>

#define STORE_KEY_MAX 64

/* Immutable, reference-counted value. Readers hold a reference while they
 * transmit it, so the store lock is never held during network I/O. */
typedef struct blob blob;

const unsigned char *blob_data(const blob *b);
size_t blob_len(const blob *b);
void blob_release(blob *b);

typedef struct store store;

store *store_new(void);
void store_free(store *s);

typedef enum { STORE_OK, STORE_CREATED, STORE_NOMEM } store_put_result;

/* Copies `len` bytes from `data`. Returns STORE_CREATED for a new key,
 * STORE_OK when replacing an existing value. */
store_put_result store_put(store *s, const char *key, const void *data, size_t len);

/* Returns a new reference (release with blob_release) or NULL if absent. */
blob *store_get(store *s, const char *key);

/* Returns true if the key existed and was removed. */
bool store_delete(store *s, const char *key);

/* Returns a malloc'd array of malloc'd key strings, sorted ascending by
 * byte value. Caller frees via store_keys_free. Returns NULL on OOM. */
char **store_keys(store *s, size_t *count);
void store_keys_free(char **keys, size_t count);

#endif
