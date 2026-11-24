/* Single-threaded, non-blocking HTTP server built on poll(2). */
#ifndef KVHTTP_SERVER_H
#define KVHTTP_SERVER_H

#include <stdint.h>

#include "store.h"

/* Binds 127.0.0.1:port and serves forever. Returns only on fatal error,
 * with a nonzero value. */
int server_run(uint16_t port, kv_store *store);

#endif
