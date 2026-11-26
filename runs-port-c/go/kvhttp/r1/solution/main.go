// Command kvhttp is an HTTP/1.1 in-memory key-value server.
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
	port, err := strconv.Atoi(os.Args[1])
	if err != nil || port < 1 || port > 65535 {
		fmt.Fprintf(os.Stderr, "invalid port: %s\n", os.Args[1])
		os.Exit(2)
	}

	ln, err := net.Listen("tcp", net.JoinHostPort("127.0.0.1", strconv.Itoa(port)))
	if err != nil {
		log.Fatal(err)
	}

	srv := &http.Server{
		Handler:           server.New(store.New()),
		ReadHeaderTimeout: 10 * time.Second,
		ReadTimeout:       30 * time.Second,
		WriteTimeout:      30 * time.Second,
		IdleTimeout:       30 * time.Second,
		MaxHeaderBytes:    16 << 10,
	}
	log.Fatal(srv.Serve(ln))
}
