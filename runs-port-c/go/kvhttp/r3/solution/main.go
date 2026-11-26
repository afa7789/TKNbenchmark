// Command app is an in-memory HTTP/1.1 key-value server.
//
// Usage: app <port>
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
		ReadHeaderTimeout: 10 * time.Second,
		ReadTimeout:       30 * time.Second,
		WriteTimeout:      30 * time.Second,
		IdleTimeout:       30 * time.Second,
		MaxHeaderBytes:    64 << 10,
		ErrorLog:          log.New(os.Stderr, "http: ", log.LstdFlags),
	}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	errc := make(chan error, 1)
	go func() { errc <- srv.Serve(ln) }()

	select {
	case err := <-errc:
		return err
	case <-ctx.Done():
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		if err := srv.Shutdown(shutdownCtx); err != nil {
			return err
		}
		if err := <-errc; !errors.Is(err, http.ErrServerClosed) {
			return err
		}
		return nil
	}
}
