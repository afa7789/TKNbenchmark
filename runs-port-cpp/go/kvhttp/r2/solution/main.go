// Command app is an HTTP/1.1 in-memory key-value server.
//
// Usage:
//
//	app <port>
//
// It listens on 127.0.0.1:<port> and serves until killed.
package main

import (
	"fmt"
	"log"
	"net"
	"net/http"
	"os"
	"strconv"
	"time"
)

const (
	maxHeaderBytes = 64 << 10
	ioTimeout      = 10 * time.Second
)

func main() {
	log.SetFlags(0)
	if len(os.Args) != 2 {
		fmt.Fprintf(os.Stderr, "usage: %s <port>\n", os.Args[0])
		os.Exit(2)
	}
	port, err := strconv.ParseUint(os.Args[1], 10, 16)
	if err != nil || port == 0 {
		fmt.Fprintf(os.Stderr, "invalid port: %s\n", os.Args[1])
		os.Exit(2)
	}

	srv := &http.Server{
		Addr:              net.JoinHostPort("127.0.0.1", strconv.FormatUint(port, 10)),
		Handler:           NewHandler(NewStore()),
		ReadHeaderTimeout: ioTimeout,
		ReadTimeout:       ioTimeout,
		WriteTimeout:      ioTimeout,
		IdleTimeout:       ioTimeout,
		MaxHeaderBytes:    maxHeaderBytes,
	}
	if err := srv.ListenAndServe(); err != nil {
		log.Fatalf("fatal: %v", err)
	}
}
