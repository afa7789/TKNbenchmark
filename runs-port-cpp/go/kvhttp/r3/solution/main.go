// Command app is an in-memory HTTP/1.1 key/value server.
//
// Usage: app <port>
package main

import (
	"fmt"
	"log"
	"net"
	"net/http"
	"os"
	"strconv"
	"time"

	"kvhttp/internal/server"
	"kvhttp/internal/store"
)

func main() {
	if len(os.Args) != 2 {
		fmt.Fprintf(os.Stderr, "usage: %s <port>\n", os.Args[0])
		os.Exit(2)
	}
	port, err := strconv.ParseUint(os.Args[1], 10, 16)
	if err != nil || port == 0 {
		fmt.Fprintf(os.Stderr, "kvhttp: invalid port %q\n", os.Args[1])
		os.Exit(2)
	}

	addr := net.JoinHostPort("127.0.0.1", strconv.FormatUint(port, 10))
	ln, err := net.Listen("tcp", addr)
	if err != nil {
		log.Fatalf("kvhttp: listen: %v", err)
	}

	srv := &http.Server{
		Handler:           server.New(store.New()),
		ReadHeaderTimeout: 30 * time.Second,
		ReadTimeout:       30 * time.Second,
		WriteTimeout:      30 * time.Second,
		IdleTimeout:       30 * time.Second,
		MaxHeaderBytes:    64 << 10,
	}
	log.Fatal(srv.Serve(ln))
}
