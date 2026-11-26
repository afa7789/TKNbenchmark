// Command kvhttp is an HTTP/1.1 in-memory key-value server.
//
// Usage:
//
//	app <port>
//
// It listens on 127.0.0.1:<port> and serves until terminated.
package main

import (
	"context"
	"errors"
	"fmt"
	"log"
	"net"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"syscall"
	"time"

	"kvhttp/internal/server"
	"kvhttp/internal/store"
)

const (
	ioTimeout      = 30 * time.Second
	maxHeaderBytes = 16 << 10
	shutdownGrace  = 5 * time.Second
)

func main() {
	if len(os.Args) != 2 {
		usage()
	}
	port, err := strconv.ParseUint(os.Args[1], 10, 16)
	if err != nil || port == 0 {
		usage()
	}
	if err := run(uint16(port)); err != nil {
		log.Fatal(err)
	}
}

func usage() {
	fmt.Fprintf(os.Stderr, "usage: %s <port>\n", os.Args[0])
	os.Exit(2)
}

func run(port uint16) error {
	addr := net.JoinHostPort("127.0.0.1", strconv.Itoa(int(port)))
	ln, err := net.Listen("tcp", addr)
	if err != nil {
		return err
	}

	srv := &http.Server{
		Handler:           server.New(store.New()),
		ReadHeaderTimeout: ioTimeout,
		ReadTimeout:       ioTimeout,
		WriteTimeout:      ioTimeout,
		IdleTimeout:       ioTimeout,
		MaxHeaderBytes:    maxHeaderBytes,
		ErrorLog:          log.New(os.Stderr, "kvhttp: ", log.LstdFlags),
	}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	errc := make(chan error, 1)
	go func() { errc <- srv.Serve(ln) }()

	select {
	case err := <-errc:
		return err
	case <-ctx.Done():
	}
	shutdownCtx, cancel := context.WithTimeout(context.Background(), shutdownGrace)
	defer cancel()
	if err := srv.Shutdown(shutdownCtx); err != nil {
		return err
	}
	if err := <-errc; !errors.Is(err, http.ErrServerClosed) {
		return err
	}
	return nil
}
