/* kvhttp: an in-memory HTTP/1.1 key-value server. Usage: app <port> */
#include <errno.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>

#include "server.h"
#include "store.h"

static int parse_port(const char *s, uint16_t *out)
{
    char *end;
    errno = 0;
    long v = strtol(s, &end, 10);
    if (errno || end == s || *end != '\0' || v < 1 || v > 65535)
        return -1;
    *out = (uint16_t)v;
    return 0;
}

int main(int argc, char **argv)
{
    uint16_t port;
    if (argc != 2 || parse_port(argv[1], &port) != 0) {
        fprintf(stderr, "usage: %s <port>\n", argc ? argv[0] : "app");
        return 2;
    }

    signal(SIGPIPE, SIG_IGN);

    kv_store *store = kv_create();
    if (!store) {
        fprintf(stderr, "out of memory\n");
        return 1;
    }
    int rc = server_run(port, store);
    kv_destroy(store);
    return rc;
}
